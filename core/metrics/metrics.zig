const std = @import("std");
const scheduler_mod = @import("scheduler");

pub fn printSummary(scheduler: *scheduler_mod.Scheduler, writer: std.Io.Writer) !void {
    try writer.print("\nQwD Analytics Summary\n", .{});
    try writer.print("=====================\n", .{});
    scheduler.report(writer);
    try writer.print("=====================\n", .{});
}
