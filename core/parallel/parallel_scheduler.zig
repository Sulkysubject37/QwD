const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const ring_buffer = @import("ring_buffer");
const block_reader = @import("block_reader");
const mode_mod = @import("mode");
const fastq_block = @import("fastq_block");
const bitplanes = @import("bitplanes");
const vertical_scanner = @import("vertical_scanner");
const bgzf_native_reader = @import("bgzf_native_reader");
const deflate_impl = @import("deflate_impl");
const custom_deflate = @import("custom_deflate");

pub const JobKind = enum { raw, compressed };
pub const Job = struct {
    data: []u8,
    uncompressed_len: u32 = 0,
    kind: JobKind,
};

pub const WorkerContext = struct {
    scheduler: *ParallelScheduler,
    stages: []stage_mod.Stage,
    block: fastq_block.FastqColumnBlock,
    bp_core: bitplanes.BitplaneCore,
    indices: []usize,
    queue: *ring_buffer.RingBuffer(Job),
    read_count_atomic: *std.atomic.Value(usize),
    mode: mode_mod.Mode,
    id: usize,
};

pub const ParallelScheduler = struct {
    sys_allocator: std.mem.Allocator,
    io: std.Io,
    num_threads: usize,
    stages: std.ArrayListUnmanaged(stage_mod.Stage),
    mode: mode_mod.Mode = .exact,
    gzip_mode: mode_mod.GzipMode = .auto,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, threads: usize, mode: mode_mod.Mode, gzip_mode: mode_mod.GzipMode) ParallelScheduler {
        return .{
            .sys_allocator = allocator,
            .io = io,
            .num_threads = threads,
            .stages = .empty,
            .mode = mode,
            .gzip_mode = gzip_mode,
        };
    }

    pub fn deinit(self: *ParallelScheduler) void {
        self.stages.deinit(self.sys_allocator);
    }

    pub fn addStage(self: *ParallelScheduler, stage: stage_mod.Stage) !void {
        try self.stages.append(self.sys_allocator, stage);
    }

    pub fn getAllocatedBytes(self: *ParallelScheduler) usize {
        const g_alloc: *@import("global_allocator").GlobalAllocator = @ptrCast(@alignCast(self.sys_allocator.ptr));
        return g_alloc.allocated_bytes.load(.acquire);
    }

    pub fn run(self: *ParallelScheduler, file: std.Io.File, pipeline_ptr: anytype) !void {
        var analyze_queue = try ring_buffer.RingBuffer(Job).init(self.sys_allocator, 8);
        defer analyze_queue.deinit();

        var threads = try self.sys_allocator.alloc(std.Thread, self.num_threads);
        defer self.sys_allocator.free(threads);

        var contexts = try self.sys_allocator.alloc(*WorkerContext, self.num_threads);
        defer self.sys_allocator.free(contexts);

        var read_count_atomic = std.atomic.Value(usize).init(0);

        for (0..self.num_threads) |i| {
            var ctx = try self.sys_allocator.create(WorkerContext);
            ctx.* = .{
                .scheduler = self,
                .stages = try self.sys_allocator.alloc(stage_mod.Stage, self.stages.items.len),
                .queue = analyze_queue,
                .read_count_atomic = &read_count_atomic,
                .mode = self.mode,
                .id = i,
                .indices = try self.sys_allocator.alloc(usize, 1024 * 1024),
                .block = try fastq_block.FastqColumnBlock.init(self.sys_allocator, 1024, 1024),
                .bp_core = try bitplanes.BitplaneCore.init(self.sys_allocator, 1024, 1024),
            };
            for (self.stages.items, 0..) |stage, j| {
                ctx.stages[j] = try stage.clone(self.sys_allocator);
            }
            contexts[i] = ctx;
            threads[i] = try std.Thread.spawn(.{}, workerEntry, .{ctx});
        }

        var magic: [2]u8 = undefined;
        const n_magic = file.readStreaming(self.io, &[_][]u8{magic[0..]}) catch 0;
        var magic_used = false;
        const is_bgzf = (n_magic == 2 and magic[0] == 0x1F and magic[1] == 0x8B);

        if (is_bgzf) {
            std.debug.print("[ParallelScheduler] Mode: BGZF-Ordered-Parallel\n", .{});
            var bgzf = try bgzf_native_reader.BgzfNativeReader.init(self.sys_allocator, undefined);
            defer bgzf.deinit();

            var carry_over: std.ArrayListUnmanaged(u8) = .empty;
            defer carry_over.deinit(self.sys_allocator);

            while (try bgzf.nextBlockHardened(file, self.io, if (magic_used) null else &magic)) |block| {
                magic_used = true;
                
                const decompressed = try self.sys_allocator.alloc(u8, block.uncompressed_len);
                
                switch (self.gzip_mode) {
                    .native => {
                        var reader = std.Io.Reader.fixed(block.compressed_data);
                        var engine = custom_deflate.DeflateEngine.init(&reader);
                        const Sink = struct {
                            out: []u8,
                            pos: usize = 0,
                            pub fn emit(s: *@This(), byte: u8) !void {
                                if (s.pos >= s.out.len) return error.BufferFull;
                                s.out[s.pos] = byte;
                                s.pos += 1;
                            }
                        };
                        var sink = Sink{ .out = decompressed };
                        try engine.decompress(&sink);
                    },
                    else => {
                        _ = try deflate_impl.decompress(block.compressed_data, decompressed);
                    }
                }
                self.sys_allocator.free(block.compressed_data);

                try carry_over.appendSlice(self.sys_allocator, decompressed);
                self.sys_allocator.free(decompressed);

                if (carry_over.items.len >= 16 * 1024 * 1024) {
                    try self.pushAligned(analyze_queue, &carry_over);
                }
            }
            if (carry_over.items.len > 0) {
                const final_data = try self.sys_allocator.alloc(u8, carry_over.items.len);
                @memcpy(final_data, carry_over.items);
                _ = analyze_queue.push(self.io, .{ .data = final_data, .kind = .raw });
            }
        } else {
            std.debug.print("[ParallelScheduler] Mode: Raw-Parallel\n", .{});
            const target_chunk_size = 16 * 1024 * 1024;
            var carry_over: std.ArrayListUnmanaged(u8) = .empty;
            defer carry_over.deinit(self.sys_allocator);

            while (true) {
                var buf = try self.sys_allocator.alloc(u8, target_chunk_size);
                const n = file.readStreaming(self.io, &[_][]u8{buf}) catch |err| if (err == error.EndOfStream) @as(usize, 0) else return err;
                if (n == 0) {
                    self.sys_allocator.free(buf);
                    break;
                }
                try carry_over.appendSlice(self.sys_allocator, buf[0..n]);
                self.sys_allocator.free(buf);
                
                if (carry_over.items.len >= target_chunk_size) {
                    try self.pushAligned(analyze_queue, &carry_over);
                }
            }
            if (carry_over.items.len > 0) {
                const final_data = try self.sys_allocator.alloc(u8, carry_over.items.len);
                @memcpy(final_data, carry_over.items);
                _ = analyze_queue.push(self.io, .{ .data = final_data, .kind = .raw });
            }
        }

        analyze_queue.shutdown(self.io, self.num_threads);
        
        for (0..self.num_threads) |i| {
            threads[i].join();
            for (self.stages.items, 0..) |global_stage, j| {
                try global_stage.merge(contexts[i].stages[j]);
            }
            contexts[i].block.deinit();
            contexts[i].bp_core.deinit();
            self.sys_allocator.free(contexts[i].indices);
            self.sys_allocator.free(contexts[i].stages);
            self.sys_allocator.destroy(contexts[i]);
        }
        
        pipeline_ptr.read_count = read_count_atomic.load(.acquire);
    }

    pub fn finalize(self: *ParallelScheduler) !void {
        _ = self;
    }

    fn pushAligned(self: *ParallelScheduler, queue: *ring_buffer.RingBuffer(Job), carry_over: *std.ArrayListUnmanaged(u8)) !void {
        const data = carry_over.items;
        var last_valid: usize = 0;
        var nl_count: usize = 0;
        var search: usize = 0;
        while (std.mem.indexOfScalarPos(u8, data, search, '\n')) |idx| {
            nl_count += 1;
            if (nl_count % 4 == 0) last_valid = idx + 1;
            search = idx + 1;
        }

        if (last_valid > 0) {
            const push_data = try self.sys_allocator.alloc(u8, last_valid);
            @memcpy(push_data, data[0..last_valid]);
            _ = queue.push(self.io, .{ .data = push_data, .kind = .raw });
            
            const rem = carry_over.items[last_valid..];
            std.mem.copyForwards(u8, carry_over.items[0..rem.len], rem);
            carry_over.items.len = rem.len;
        }
    }

    fn workerEntry(ctx: *WorkerContext) void {
        const allocator = ctx.scheduler.sys_allocator;
        const io = ctx.scheduler.io;

        while (true) {
            const job = ctx.queue.pop(io) orelse break;
            const active_data = job.data;

            var scan_res = vertical_scanner.FastqScanner.ScanResult{
                .indices = ctx.indices,
                .count = 0,
            };
            vertical_scanner.FastqScanner.scanNewlinesSIMD(active_data, &scan_res);
            const total_reads = scan_res.count / 4;

            if (total_reads > 0) {
                var reads_done: usize = 0;
                while (reads_done < total_reads) {
                    const chunk_size = @min(1024, total_reads - reads_done);
                    
                    ctx.block.clear();
                    ctx.block.transposeFromIndices(active_data, ctx.indices, reads_done * 4, chunk_size);
                    
                    ctx.bp_core.clear(chunk_size);
                    ctx.bp_core.fromColumnBlock(&ctx.block);

                    for (ctx.stages) |stage| {
                        _ = stage.processBitplanes(&ctx.bp_core, &ctx.block) catch {};
                    }
                    _ = ctx.read_count_atomic.fetchAdd(chunk_size, .monotonic);
                    reads_done += chunk_size;
                }
            }
            allocator.free(active_data);
        }
    }
};
