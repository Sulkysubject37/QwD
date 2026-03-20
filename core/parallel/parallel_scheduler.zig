const std = @import("std");
const parser_mod = @import("parser");
const stage_mod = @import("stage");
const fastq_block = @import("fastq_block");
const ring_buffer_mod = @import("ring_buffer");
const block_reader = @import("block_reader");
const simd_transpose = @import("simd_transpose");
const vertical_scanner = @import("vertical_scanner");
const kmer_direct = @import("kmer_direct");
const bitplanes_mod = @import("bitplanes");

pub const ParallelScheduler = struct {
    read_count: std.atomic.Value(usize),
    master_stages: std.ArrayList(stage_mod.Stage),
    num_threads: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_threads: usize) ParallelScheduler {
        return ParallelScheduler{
            .read_count = std.atomic.Value(usize).init(0),
            .master_stages = std.ArrayList(stage_mod.Stage).init(allocator),
            .num_threads = if (num_threads == 0) 1 else num_threads,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ParallelScheduler) void {
        self.master_stages.deinit();
    }

    pub fn registerStage(self: *ParallelScheduler, stage: stage_mod.Stage) !void {
        try self.master_stages.append(stage);
    }
    
    pub fn process(self: *ParallelScheduler, read: parser_mod.Read) !void {
        _ = self.read_count.fetchAdd(1, .monotonic);
        var r = read;
        for (self.master_stages.items) |stage| {
            if (!(try stage.process(&r))) break;
        }
    }
    
    pub const Chunk = struct {
        data: []const u8,
        is_alloc: bool,
    };

    const ThreadContext = struct {
        scheduler: *ParallelScheduler,
        work_queue: *ring_buffer_mod.RingBuffer(Chunk),
        done_flag: *std.atomic.Value(bool),
        stages: []stage_mod.Stage,
        arena: *std.heap.ArenaAllocator,
        col_block: *fastq_block.FastqColumnBlock,
        bitplanes: *bitplanes_mod.Bitplanes,
    };

    fn workerLoop(ctx: ThreadContext) void {
        const allocator = ctx.arena.allocator();
        const nl_buffer_len = 1000000; // Increased for short reads
        const nl_buffer = allocator.alloc(usize, nl_buffer_len) catch return;
        defer allocator.free(nl_buffer);
        
        var nl_result = vertical_scanner.FastqScanner.ScanResult{
            .indices = nl_buffer,
            .count = 0,
        };

        while (true) {
            if (ctx.work_queue.pop()) |chunk| {
                vertical_scanner.FastqScanner.scanNewlinesSIMD(chunk.data, &nl_result);
                const total_newlines = nl_result.count;
                
                var current_nl: i64 = -1; // Newline index preceding the current record
                
                // Align to the first record boundary
                if (chunk.data.len > 0 and chunk.data[0] != '@') {
                    var found = false;
                    for (0..total_newlines) |idx| {
                        const nl_pos = nl_result.indices[idx];
                        if (nl_pos + 1 < chunk.data.len and chunk.data[nl_pos + 1] == '@') {
                            current_nl = @intCast(idx);
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        if (chunk.is_alloc) ctx.scheduler.allocator.free(chunk.data);
                        continue;
                    }
                }

                while (current_nl + 4 < total_newlines) {
                    const rc: usize = @min(1024, (total_newlines - @as(usize, @intCast(current_nl + 1))) / 4);
                    
                    if (rc > 0) {
                        _ = ctx.scheduler.read_count.fetchAdd(rc, .monotonic);
                        
                        ctx.col_block.clear();
                        ctx.col_block.transposeFromIndices(chunk.data, nl_result.indices, current_nl, rc);

                        // GENERATE BITPLANES ONCE
                        ctx.bitplanes.fromColumnBlock(ctx.col_block);

                        for (ctx.stages) |stage| {
                            _ = stage.processBitplanes(ctx.bitplanes, ctx.col_block) catch break;
                        }
                        
                        current_nl += @intCast(rc * 4);
                    } else break;
                }
                
                if (chunk.is_alloc) ctx.scheduler.allocator.free(chunk.data);
            } else {
                if (ctx.done_flag.load(.acquire)) break;
                std.Thread.yield() catch {};
            }
        }
    }

    pub fn run_chunked(self: *ParallelScheduler, chunk_builder: anytype, pipeline_ptr: anytype) !void {
        const queue_depth = 64;
        const batch_size = 1024;
        var work_queue = try ring_buffer_mod.RingBuffer(Chunk).init(self.allocator, queue_depth);
        defer work_queue.deinit();
        var done_flag = std.atomic.Value(bool).init(false);
        var threads = try self.allocator.alloc(std.Thread, self.num_threads);
        defer self.allocator.free(threads);
        var thread_contexts = try self.allocator.alloc(ThreadContext, self.num_threads);
        defer self.allocator.free(thread_contexts);

        for (0..self.num_threads) |t_idx| {
            var arena = try self.allocator.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(self.allocator);
            
            const col_block = try arena.allocator().create(fastq_block.FastqColumnBlock);
            col_block.* = try fastq_block.FastqColumnBlock.init(arena.allocator(), batch_size, 500);

            const bps = try arena.allocator().create(bitplanes_mod.Bitplanes);
            bps.* = try bitplanes_mod.Bitplanes.init(arena.allocator(), batch_size, 500);


            var t_stages = std.ArrayList(stage_mod.Stage).init(arena.allocator());
            for (pipeline_ptr.stage_names.items) |name| {
                try t_stages.append(try pipeline_ptr.createStageInstance(arena.allocator(), name));
            }

            thread_contexts[t_idx] = .{
                .scheduler = self,
                .work_queue = work_queue,
                .done_flag = &done_flag,
                .stages = try t_stages.toOwnedSlice(),
                .arena = arena,
                .col_block = col_block,
                .bitplanes = bps,
            };
            threads[t_idx] = try std.Thread.spawn(.{}, workerLoop, .{ thread_contexts[t_idx] });
        }

        while (true) {
            if (try chunk_builder.nextChunk()) |raw_chunk| {
                var c = Chunk{ .data = raw_chunk, .is_alloc = false };
                if (!chunk_builder.br.is_mmap) {
                    c.data = try self.allocator.dupe(u8, raw_chunk);
                    c.is_alloc = true;
                }
                while (!work_queue.push(c)) std.Thread.yield() catch {};
            } else break;
        }
        done_flag.store(true, .release);
        for (threads) |thread| thread.join();
        for (thread_contexts) |ctx| {
            for (0..self.master_stages.items.len) |s_idx| try self.master_stages.items[s_idx].merge(ctx.stages[s_idx]);
            ctx.arena.deinit();
            self.allocator.destroy(ctx.arena);
        }
    }

    pub fn finalize(self: *ParallelScheduler) !void {
        for (self.master_stages.items) |stage| try stage.finalize();
    }

    pub fn report(self: *ParallelScheduler, writer: std.io.AnyWriter) void {
        for (self.master_stages.items) |stage| stage.report(writer);
    }
};
