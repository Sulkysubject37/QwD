const std = @import("std");

pub fn indexOfNewline(buffer: []const u8) ?usize {
    // std.mem.indexOfScalar internally uses heavily optimized SIMD on supported platforms.
    return std.mem.indexOfScalar(u8, buffer, '\n');
}
