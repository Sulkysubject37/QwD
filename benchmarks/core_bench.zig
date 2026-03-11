const std = @import("std");
const parser_mod = @import("parser");
const scheduler_mod = @import("scheduler");
const parallel_scheduler_mod = @import("parallel_scheduler");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const num_reads = 100_000;
    std.debug.print("Benchmarking single vs multi-core scheduling ({d} reads)...\n", .{num_reads});

    // Mock read
    const read = parser_mod.Read{
        .id = "mock",
        .seq = "A" ** 100,
        .qual = "I" ** 100,
    };

    // Single-core
    var scheduler = scheduler_mod.Scheduler.init(allocator);
    defer scheduler.deinit();
    
    var timer = try std.time.Timer.start();
    for (0..num_reads) |_| {
        try scheduler.process(read);
    }
    const t_single = timer.read();

    // Multi-core (using ParallelScheduler framework)
    var p_scheduler = parallel_scheduler_mod.ParallelScheduler.init(allocator, 4);
    defer p_scheduler.deinit();
    
    timer.reset();
    for (0..num_reads) |_| {
        try p_scheduler.process(read);
    }
    const t_multi = timer.read();

    std.debug.print("Single-core: {d:>12} ns\n", .{t_single});
    std.debug.print("Multi-core:  {d:>12} ns\n", .{t_multi});
}
