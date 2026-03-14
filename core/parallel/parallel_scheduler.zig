const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const read_batch_mod = @import("read_batch");
const ring_buffer_mod = @import("ring_buffer");

pub const ParallelScheduler = struct {
    read_count: std.atomic.Value(usize),
    // The master stage list for reporting and final aggregation
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

    pub fn process(self: *ParallelScheduler, read: parser.Read) !void {
        _ = self.read_count.fetchAdd(1, .monotonic);
        var r = read;
        for (self.master_stages.items) |stage| {
            if (!(try stage.process(&r))) break;
        }
    }
    
    const ThreadContext = struct {
        scheduler: *ParallelScheduler,
        work_queue: *ring_buffer_mod.RingBuffer(*read_batch_mod.ReadBatch),
        free_queue: *ring_buffer_mod.RingBuffer(*read_batch_mod.ReadBatch),
        done_flag: *std.atomic.Value(bool),
        stages: []stage_mod.Stage,
        arena: *std.heap.ArenaAllocator,
    };

    fn workerLoop(ctx: ThreadContext) void {
        while (true) {
            if (ctx.work_queue.pop()) |batch| {
                for (0..batch.count) |i| {
                    var r = parser.Read{
                        .id = "mock",
                        .seq = batch.sequences[i],
                        .qual = batch.qualities[i],
                    };
                    
                    _ = ctx.scheduler.read_count.fetchAdd(1, .monotonic);
                    for (ctx.stages) |stage| {
                        _ = stage.process(&r) catch break;
                    }
                }
                // Return batch to free queue
                while (!ctx.free_queue.push(batch)) {
                    std.Thread.yield() catch {};
                }
            } else {
                if (ctx.done_flag.load(.acquire)) {
                    // Exhaust the remaining queue before breaking
                    while (ctx.work_queue.pop()) |batch| {
                         for (0..batch.count) |i| {
                            var r = parser.Read{
                                .id = "mock",
                                .seq = batch.sequences[i],
                                .qual = batch.qualities[i],
                            };
                            _ = ctx.scheduler.read_count.fetchAdd(1, .monotonic);
                            for (ctx.stages) |stage| {
                                _ = stage.process(&r) catch break;
                            }
                        }
                    }
                    break;
                }
                std.Thread.yield() catch {};
            }
        }
    }

    pub fn run_batches(self: *ParallelScheduler, batch_builder: anytype, pipeline_ptr: anytype) !void {
        if (self.num_threads <= 1) {
            // Use a local batch for sequential processing
            var batch = try read_batch_mod.ReadBatch.init(self.allocator, 4096);
            defer batch.deinit(self.allocator);

            while (try batch_builder.fillBatch(&batch)) {
                for (0..batch.count) |i| {
                    const r = parser.Read{
                        .id = "mock", 
                        .seq = batch.sequences[i],
                        .qual = batch.qualities[i],
                    };
                    try self.process(r);
                }
            }
            return;
        }

        const queue_depth = 64;
        var work_queue = try ring_buffer_mod.RingBuffer(*read_batch_mod.ReadBatch).init(self.allocator, queue_depth);
        defer work_queue.deinit();
        var free_queue = try ring_buffer_mod.RingBuffer(*read_batch_mod.ReadBatch).init(self.allocator, queue_depth);
        defer free_queue.deinit();

        // Initialize batches and put in free queue
        var batches = try self.allocator.alloc(read_batch_mod.ReadBatch, queue_depth);
        defer self.allocator.free(batches);
        for (0..queue_depth) |i| {
            batches[i] = try read_batch_mod.ReadBatch.init(self.allocator, 4096);
            _ = free_queue.push(&batches[i]);
        }
        defer {
            for (0..queue_depth) |i| {
                batches[i].deinit(self.allocator);
            }
        }

        var done_flag = std.atomic.Value(bool).init(false);
        var threads = try self.allocator.alloc(std.Thread, self.num_threads);
        defer self.allocator.free(threads);

        var thread_contexts = try self.allocator.alloc(ThreadContext, self.num_threads);
        defer self.allocator.free(thread_contexts);

        // Create thread-local pipelines
        for (0..self.num_threads) |t_idx| {
            var arena = try self.allocator.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(self.allocator);
            
            var t_stages = std.ArrayList(stage_mod.Stage).init(arena.allocator());
            for (pipeline_ptr.stage_names.items) |name| {
                try t_stages.append(try pipeline_ptr.createStageInstance(arena.allocator(), name));
            }

            thread_contexts[t_idx] = .{
                .scheduler = self,
                .work_queue = work_queue,
                .free_queue = free_queue,
                .done_flag = &done_flag,
                .stages = try t_stages.toOwnedSlice(),
                .arena = arena,
            };
            threads[t_idx] = try std.Thread.spawn(.{}, workerLoop, .{ thread_contexts[t_idx] });
        }

        // Producer
        while (true) {
            // Get free batch
            const batch = while (true) {
                if (free_queue.pop()) |b| break b;
                std.Thread.yield() catch {};
            };

            if (try batch_builder.fillBatch(batch)) {
                while (!work_queue.push(batch)) {
                    std.Thread.yield() catch {};
                }
            } else {
                // EOF, return batch and break
                _ = free_queue.push(batch);
                break;
            }
        }

        done_flag.store(true, .release);

        for (threads) |thread| {
            thread.join();
        }

        // Merge thread-local metrics into master stages
        for (thread_contexts) |ctx| {
            for (0..self.master_stages.items.len) |s_idx| {
                try self.master_stages.items[s_idx].merge(ctx.stages[s_idx]);
            }
            ctx.arena.deinit();
            self.allocator.destroy(ctx.arena);
        }
    }

    pub fn finalize(self: *ParallelScheduler) !void {
        for (self.master_stages.items) |stage| {
            try stage.finalize();
        }
    }

    pub fn report(self: *ParallelScheduler, writer: std.io.AnyWriter) void {
        for (self.master_stages.items) |stage| {
            stage.report(writer);
        }
    }
};
