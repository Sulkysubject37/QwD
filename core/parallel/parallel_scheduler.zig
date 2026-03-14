const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const read_batch_mod = @import("read_batch");
const ring_buffer_mod = @import("ring_buffer");

pub const ParallelScheduler = struct {
    read_count: std.atomic.Value(usize),
    stages: std.ArrayList(stage_mod.Stage),
    num_threads: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_threads: usize) ParallelScheduler {
        return ParallelScheduler{
            .read_count = std.atomic.Value(usize).init(0),
            .stages = std.ArrayList(stage_mod.Stage).init(allocator),
            .num_threads = if (num_threads == 0) 1 else num_threads,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ParallelScheduler) void {
        self.stages.deinit();
    }

    pub fn registerStage(self: *ParallelScheduler, stage: stage_mod.Stage) !void {
        try self.stages.append(stage);
    }

    pub fn process(self: *ParallelScheduler, read: parser.Read) !void {
        // Fallback for single read processing
        var r = read;
        _ = self.read_count.fetchAdd(1, .monotonic);
        for (self.stages.items) |stage| {
            if (!(try stage.process(&r))) break;
        }
    }
    
    // Worker thread function
    fn workerLoop(self: *ParallelScheduler, rb: *ring_buffer_mod.RingBuffer(*read_batch_mod.ReadBatch), done_flag: *std.atomic.Value(bool)) void {
        while (true) {
            if (rb.pop()) |batch_ptr| {
                const batch = batch_ptr.*;
                for (0..batch.count) |i| {
                    var r = parser.Read{
                        .id = "mock",
                        .seq = batch.sequences[i],
                        .qual = batch.qualities[i],
                    };
                    
                    _ = self.read_count.fetchAdd(1, .monotonic);
                    for (self.stages.items) |stage| {
                        _ = stage.process(&r) catch break;
                    }
                }
            } else {
                if (done_flag.load(.acquire)) {
                    if (rb.pop()) |batch_ptr| {
                         const batch = batch_ptr.*;
                         for (0..batch.count) |i| {
                            var r = parser.Read{
                                .id = "mock",
                                .seq = batch.sequences[i],
                                .qual = batch.qualities[i],
                            };
                            _ = self.read_count.fetchAdd(1, .monotonic);
                            for (self.stages.items) |stage| {
                                _ = stage.process(&r) catch break;
                            }
                        }
                        continue;
                    }
                    break;
                }
                std.Thread.yield() catch {};
            }
        }
    }

    pub fn run_batches(self: *ParallelScheduler, batch_builder: anytype) !void {
        if (self.num_threads <= 1) {
            // Sequential fallback if only 1 thread
            while (try batch_builder.nextBatch()) |batch| {
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

        // Initialize Ring Buffer
        const queue_depth = 32;
        var rb = try ring_buffer_mod.RingBuffer(*read_batch_mod.ReadBatch).init(self.allocator, queue_depth);
        defer rb.deinit();

        var done_flag = std.atomic.Value(bool).init(false);

        // Spawn workers
        var threads = try self.allocator.alloc(std.Thread, self.num_threads);
        defer self.allocator.free(threads);

        for (0..self.num_threads) |i| {
            threads[i] = try std.Thread.spawn(.{}, workerLoop, .{ self, rb, &done_flag });
        }

        // Producer Loop
        while (try batch_builder.nextBatch()) |batch| {
            // Spin until we can push to the bounded queue
            while (!rb.push(batch)) {
                std.Thread.yield() catch {};
            }
        }

        // Signal workers to terminate
        done_flag.store(true, .release);

        // Wait for workers
        for (threads) |thread| {
            thread.join();
        }
    }

    pub fn finalize(self: *ParallelScheduler) !void {
        for (self.stages.items) |stage| {
            try stage.finalize();
        }
    }

    pub fn report(self: *ParallelScheduler, writer: std.io.AnyWriter) void {
        for (self.stages.items) |stage| {
            stage.report(writer);
        }
    }
};
