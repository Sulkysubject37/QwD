const std = @import("std");
const scheduler_mod = @import("scheduler");

pub fn printSummary(scheduler: *scheduler_mod.Scheduler) void {
    std.debug.print("\nQwD Analytics Summary\n", .{});
    std.debug.print("=====================\n", .{});
    scheduler.report();
    std.debug.print("=====================\n", .{});
}
