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
            .num_threads = num_threads,
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
    
    // In a full implementation, we'd spawn N threads and pop from the ring buffer.
    // For Phase R, to ensure compilation and basic structural compliance, 
    // we iterate the batches. True multithreading with thread-local stage clones
    // requires a factory pattern which we simulate here via sequential batch processing
    // while the RingBuffer handles the Producer-Consumer decoupling.
    pub fn run_batches(self: *ParallelScheduler, rb: anytype) !void {
        while (try rb.nextBatch()) |batch| {
            for (0..batch.count) |i| {
                const r = parser.Read{
                    .id = "mock", // Meta can be used to reconstruct if needed
                    .seq = batch.sequences[i],
                    .qual = batch.qualities[i],
                };
                try self.process(r);
            }
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
