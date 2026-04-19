const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const ring_buffer = @import("ring_buffer");
const bgzf_native_reader = @import("bgzf_native_reader");
const deflate_impl = @import("deflate_impl");
const fastq_block = @import("fastq_block");
const bitplanes = @import("bitplanes");
const vertical_scanner = @import("vertical_scanner");

const Io = std.Io;

pub const ParallelScheduler = struct {
    num_threads: usize,
    sys_allocator: std.mem.Allocator,
    io: Io,
    stages: std.ArrayListUnmanaged(stage_mod.Stage),
    
    const Job = struct {
        data: []u8,
        uncompressed_len: u32 = 0,
    };

    const WorkerContext = struct {
        id: usize,
        scheduler: *const ParallelScheduler,
        in_queue: *ring_buffer.RingBuffer(Job),
        read_count: *std.atomic.Value(usize),
        stages: []stage_mod.Stage, 
        indices: []usize,
        block: fastq_block.FastqColumnBlock,
        bp_core: bitplanes.BitplaneCore,
    };

    pub fn init(allocator: std.mem.Allocator, num_threads: usize, io: Io) !ParallelScheduler {
        return ParallelScheduler{
            .num_threads = num_threads,
            .sys_allocator = allocator,
            .io = io,
            .stages = .empty,
        };
    }

    pub fn deinit(self: *ParallelScheduler) void {
        self.stages.deinit(self.sys_allocator);
    }

    pub fn addStage(self: *ParallelScheduler, stage: stage_mod.Stage) !void {
        try self.stages.append(self.sys_allocator, stage);
    }

    pub fn run(self: *ParallelScheduler, file: std.Io.File, pipeline_ptr: anytype) !void {
        std.debug.print("[ParallelScheduler] Initializing {d} workers...\n", .{self.num_threads});
        
        var analyze_queue = try ring_buffer.RingBuffer(Job).init(self.sys_allocator, 256);
        defer analyze_queue.deinit();

        var read_count_atomic = std.atomic.Value(usize).init(0);
        var threads = try self.sys_allocator.alloc(std.Thread, self.num_threads);
        var contexts = try self.sys_allocator.alloc(*WorkerContext, self.num_threads);
        defer self.sys_allocator.free(threads);
        defer self.sys_allocator.free(contexts);

        for (0..self.num_threads) |i| {
            const local_stages = try self.sys_allocator.alloc(stage_mod.Stage, self.stages.items.len);
            for (self.stages.items, 0..) |s, j| {
                local_stages[j] = try s.clone(self.sys_allocator);
            }

            const ctx = try self.sys_allocator.create(WorkerContext);
            ctx.* = .{
                .id = i,
                .scheduler = self,
                .in_queue = analyze_queue,
                .read_count = &read_count_atomic,
                .stages = local_stages,
                .indices = try self.sys_allocator.alloc(usize, 16384),
                .block = try fastq_block.FastqColumnBlock.init(self.sys_allocator, 1024, 512),
                .bp_core = try bitplanes.BitplaneCore.init(self.sys_allocator, 1024, 512),
            };
            contexts[i] = ctx;
            threads[i] = try std.Thread.spawn(.{}, workerEntry, .{ctx});
        }

        var bgzf = try bgzf_native_reader.BgzfNativeReader.init(self.sys_allocator, undefined);
        defer bgzf.deinit();

        while (try bgzf.nextBlock(file, self.io)) |block| {
            _ = analyze_queue.push(self.io, .{
                .data = block.compressed_data,
                .uncompressed_len = block.uncompressed_len,
            });
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
        
        for (self.stages.items) |stage| {
            try stage.finalize();
        }
        
        pipeline_ptr.read_count = read_count_atomic.load(.acquire);
    }

    fn workerEntry(ctx: *WorkerContext) void {
        const allocator = ctx.scheduler.sys_allocator;
        const io = ctx.scheduler.io;

        while (true) {
            const job_opt = ctx.in_queue.pop(io);
            if (job_opt) |j| {
                const decompressed = allocator.alloc(u8, j.uncompressed_len) catch {
                    allocator.free(j.data);
                    continue;
                };

                _ = deflate_impl.decompress(j.data, decompressed) catch {
                    allocator.free(j.data);
                    allocator.free(decompressed);
                    continue;
                };
                allocator.free(j.data);

                var scan_res = vertical_scanner.FastqScanner.ScanResult{
                    .indices = ctx.indices,
                    .count = 0,
                };
                vertical_scanner.FastqScanner.scanNewlinesSIMD(decompressed, &scan_res);

                const total_reads = scan_res.count / 4;
                var reads_processed: usize = 0;
                while (reads_processed < total_reads) {
                    const batch_size = @min(1024, total_reads - reads_processed);
                    ctx.block.clear();
                    ctx.block.transposeFromIndices(decompressed, ctx.indices, @intCast(reads_processed), batch_size);
                    ctx.bp_core.fromColumnBlock(ctx.block);

                    for (ctx.stages) |s| {
                        const vt = s.vtable;
                        if (vt.processBitplanes) |bp_fn| {
                            _ = bp_fn(s.ptr, &ctx.bp_core, &ctx.block) catch {};
                        } else {
                            for (0..batch_size) |idx| {
                                const start = ctx.indices[(reads_processed + idx) * 4];
                                const end = ctx.indices[(reads_processed + idx) * 4 + 1];
                                const read = parser.Read{
                                    .id = "b",
                                    .seq = decompressed[start+1..end],
                                    .qual = "!",
                                };
                                _ = s.processRead(&read) catch {};
                            }
                        }
                    }
                    reads_processed += batch_size;
                }
                _ = ctx.read_count.fetchAdd(total_reads, .monotonic);
                allocator.free(decompressed);
            } else break;
        }
        for (ctx.stages) |s| s.finalize() catch {};
    }

    pub fn finalize(_: *ParallelScheduler) !void {}

    pub fn report(self: *ParallelScheduler, writer: *std.Io.Writer) void {
        writer.print("Parallel Execution Engine: {d} threads\n", .{self.num_threads}) catch {};
    }
    pub fn reportJson(self: *ParallelScheduler, writer: *std.Io.Writer) !void {
        try writer.print("\"parallel_execution\": {{\"threads\": {d}, \"engine\": \"native_parallel\"}}", .{self.num_threads});
    }
};

const FileReader = struct {
    file: std.Io.File,
    io: std.Io,
    internal_buf: [65536]u8 = undefined,
    reader_instance: std.Io.Reader = undefined,

    pub fn stream(r: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *@This() = @fieldParentPtr("reader_instance", r);
        const available = writer.buffer.len - writer.end;
        const limit_val = @intFromEnum(limit);
        const to_read = if (limit_val == 0) available else @min(available, limit_val);
        if (to_read == 0) return 0;
        const iov = [_][]u8{writer.buffer[writer.end .. writer.end + to_read]};
        const n = self.file.readStreaming(self.io, &iov) catch |err| if (err == error.EndOfStream) return error.EndOfStream else return error.ReadFailed;
        writer.end += n;
        return n;
    }
    const VTABLE = std.Io.Reader.VTable{ .stream = stream };
    pub fn init(file: std.Io.File, io: std.Io) FileReader {
        var self = FileReader{ .file = file, .io = io };
        self.reader_instance = .{ .vtable = &VTABLE, .buffer = &self.internal_buf, .seek = 0, .end = 0 };
        return self;
    }
};
