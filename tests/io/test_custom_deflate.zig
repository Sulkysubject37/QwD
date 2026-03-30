const std = @import("std");
const DeflateEngine = @import("../../core/io/custom_deflate.zig").DeflateEngine;

const BufferSink = struct {
    buf: std.ArrayList(u8),
    pub fn emit(self: *BufferSink, byte: u8) !void {
        try self.buf.append(byte);
    }
};

test "DeflateEngine: decompress simple string" {
    const allocator = std.testing.allocator;
    
    // "Hello QwD!" compressed with gzip -n (deflate)
    // Raw deflate data starts after the 10-byte header
    const compressed = [_]u8{ 
        0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, // header
        0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x57, 0x50, 0x2c, 0x4f, 0x51, 0x54, 0x04, 0x00, // data
        0x41, 0xe1, 0xdb, 0x25, 0x0a, 0x00, 0x00, 0x00 // trailer
    };
    
    // We skip the header (10)
    var fbs = std.io.fixedBufferStream(compressed[10..]);
    var engine = DeflateEngine.init(fbs.reader().any());
    
    var sink = BufferSink{ .buf = std.ArrayList(u8).init(allocator) };
    defer sink.buf.deinit();
    
    try engine.decompressBlock(&sink);
    
    try std.testing.expectEqualStrings("Hello QwD!", sink.buf.items);
}
