const std = @import("std");
const qwd = @import("qwd_api");

pub fn main() void {
    const t = qwd.qwd_telemetry_t;
    std.debug.print("--- ZIG TELEMETRY ABI REPORT ---\n", .{});
    std.debug.print("Total Size: {d} bytes\n", .{@sizeOf(t)});
    std.debug.print("Alignment: {d} bytes\n", .{@alignOf(t)});
    std.debug.print("\nFIELD OFFSETS:\n", .{});
    std.debug.print("read_count:   {d}\n", .{@offsetOf(t, "read_count")});
    std.debug.print("total_bases:  {d}\n", .{@offsetOf(t, "total_bases")});
    std.debug.print("status:       {d}\n", .{@offsetOf(t, "status")});
    std.debug.print("gc_dist:      {d}\n", .{@offsetOf(t, "gc_distribution")});
    std.debug.print("len_dist:     {d}\n", .{@offsetOf(t, "length_distribution")});
    std.debug.print("heatmap:      {d}\n", .{@offsetOf(t, "quality_heatmap")});
}
