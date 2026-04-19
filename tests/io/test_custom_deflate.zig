const std = @import("std");
const DeflateEngine = @import("custom_deflate").DeflateEngine;

/// Minimal SliceReader to satisfy std.Io.Reader in Zig 0.16.0-dev tests
const SliceReader = struct {
    data: []const u8 = &.{},
    pos: usize = 0,
    internal_buf: [1024]u8 = undefined,

    var instance: SliceReader = .{};

    pub fn stream(_: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const available = instance.data.len - instance.pos;
        if (available == 0) return error.EndOfStream;
        
        const limit_val = @intFromEnum(limit);
        const to_read = if (limit_val == 0) available else @min(available, limit_val);

        try writer.writeAll(instance.data[instance.pos .. instance.pos + to_read]);
        instance.pos += to_read;
        return to_read;
    }

    pub fn readVec(_: *std.Io.Reader, data: [][]u8) std.Io.Reader.Error!usize {
        if (data.len == 0) return 0;
        
        const available = instance.data.len - instance.pos;
        if (available == 0) return error.EndOfStream;

        const to_read = @min(available, data[0].len);
        @memcpy(data[0][0..to_read], instance.data[instance.pos .. instance.pos + to_read]);
        instance.pos += to_read;
        return to_read;
    }

    const VTABLE = std.Io.Reader.VTable{
        .stream = stream,
        .readVec = readVec,
    };

    pub fn reader() std.Io.Reader {
        return .{
            .vtable = &VTABLE,
            .buffer = &instance.internal_buf,
            .seek = 0,
            .end = 0,
        };
    }
};

const BufferSink = struct {
    buf: std.ArrayList(u8),
    pub fn emit(self: *BufferSink, byte: u8) !void {
        try self.buf.append(byte);
    }
};

test "DeflateEngine: decompress simple string" {
    const allocator = std.testing.allocator;
    
    // "Hello QwD!" compressed with gzip -n (deflate)
    const compressed = [_]u8{ 
        0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, // header
        0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x57, 0x50, 0x2c, 0x4f, 0x51, 0x54, 0x04, 0x00, // data
        0x41, 0xe1, 0xdb, 0x25, 0x0a, 0x00, 0x00, 0x00 // trailer
    };
    
    const sr_data = compressed[10..];
    SliceReader.instance = .{ .data = &sr_data };
    var engine = DeflateEngine.init(SliceReader.reader());
    
    var sink = BufferSink{ .buf = std.ArrayList(u8).init(allocator) };
    defer sink.buf.deinit();
    
    try engine.decompress(&sink);
    
    try std.testing.expectEqualStrings("Hello QwD!", sink.buf.items);
}
