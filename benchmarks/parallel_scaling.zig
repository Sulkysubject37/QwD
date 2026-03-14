const std = @import("std");
const parser_mod = @import("parser");
const scheduler_mod = @import("scheduler");
const parallel_scheduler_mod = @import("parallel_scheduler");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const num_reads = 100_000;
    std.debug.print("Benchmarking Parallel Scaling ({d} reads)...\n", .{num_reads});

    // Mock read
    const read = parser_mod.Read{
        .id = "mock",
        .seq = "A" ** 100,
        .qual = "I" ** 100,
    };

    var timer = try std.time.Timer.start();
    
    // 1 Thread
    var s1 = parallel_scheduler_mod.ParallelScheduler.init(allocator, 1);
    defer s1.deinit();
    timer.reset();
    for (0..num_reads) |_| {
        try s1.process(read);
    }
    const t1 = timer.read();
    std.debug.print("1 Thread:  {d:>12} ns\n", .{t1});

    // 2 Threads
    var s2 = parallel_scheduler_mod.ParallelScheduler.init(allocator, 2);
    defer s2.deinit();
    timer.reset();
    for (0..num_reads) |_| {
        try s2.process(read);
    }
    const t2 = timer.read();
    std.debug.print("2 Threads: {d:>12} ns\n", .{t2});

    // 4 Threads
    var s4 = parallel_scheduler_mod.ParallelScheduler.init(allocator, 4);
    defer s4.deinit();
    timer.reset();
    for (0..num_reads) |_| {
        try s4.process(read);
    }
    const t4 = timer.read();
    std.debug.print("4 Threads: {d:>12} ns\n", .{t4});

    // 8 Threads
    var s8 = parallel_scheduler_mod.ParallelScheduler.init(allocator, 8);
    defer s8.deinit();
    timer.reset();
    for (0..num_reads) |_| {
        try s8.process(read);
    }
    const t8 = timer.read();
    std.debug.print("8 Threads: {d:>12} ns\n", .{t8});
}
