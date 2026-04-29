const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Simplest way to get 10M reads: loop and print
    var stdout_buffer: [4096]u8 = undefined;
    var io_threaded = std.Io.Threaded.init(allocator, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();
    
    var writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const iface = &writer.interface;

    const total: usize = 10_000_000;
    for (0..total) |i| {
        try iface.print("@READ_{d}\n", .{i});
        try iface.print("GATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGA\n", .{});
        try iface.print("+\n", .{});
        try iface.print("IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n", .{});
    }
}
