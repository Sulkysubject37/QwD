const std = @import("std");

pub fn main() void {
    const allocator = std.heap.page_allocator;
    var aw = std.Io.Writer.Allocating.init(allocator);
    _ = aw;
}
