const std = @import("std");
const BitSieve = @import("bit_sieve").BitSieve;

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

test "BitSieve: basic bit extraction" {
    const data = [_]u8{ 0b10101010, 0b11001100 }; // 0xAA, 0xCC
    SliceReader.instance = .{ .data = &data };
    var sieve = BitSieve.init(SliceReader.reader());

    try sieve.refill();
    
    // Peek 4 bits: should be 1010 (10)
    try std.testing.expectEqual(@as(u64, 10), sieve.peekBits(4));
    
    // Read 4 bits
    try std.testing.expectEqual(@as(u64, 10), try sieve.readBits(4));
    
    // Next 4 bits of first byte: 1010 (10)
    try std.testing.expectEqual(@as(u64, 10), try sieve.readBits(4));
    
    // First 4 bits of second byte: 1100 (12)
    try std.testing.expectEqual(@as(u64, 12), try sieve.readBits(4));
}

test "BitSieve: multi-byte refill" {
    const data = [_]u8{ 0xFF, 0x00, 0xAA, 0x55 };
    SliceReader.instance = .{ .data = &data };
    var sieve = BitSieve.init(SliceReader.reader());

    try sieve.refill();
    try std.testing.expect(sieve.bit_count >= 32);
    
    try std.testing.expectEqual(@as(u64, 0xFF), try sieve.readBits(8));
    try std.testing.expectEqual(@as(u64, 0x00), try sieve.readBits(8));
    try std.testing.expectEqual(@as(u64, 0xAA), try sieve.readBits(8));
    try std.testing.expectEqual(@as(u64, 0x55), try sieve.readBits(8));
}
