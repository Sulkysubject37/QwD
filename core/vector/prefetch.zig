const std = @import("std");

pub inline fn prefetch(ptr: anytype) void {
    // 0: load, 1: read
    // 3: high locality
    @prefetch(ptr, .{ .rw = .read, .locality = 3, .cache = .data });
}
