const std = @import("std");
const BitSieve = @import("../../core/io/bit_sieve.zig").BitSieve;

test "BitSieve: basic bit extraction" {
    const data = [_]u8{ 0b10101010, 0b11001100 }; // 0xAA, 0xCC
    var fbs = std.io.fixedBufferStream(&data);
    var sieve = BitSieve.init(fbs.reader().any());

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
    var fbs = std.io.fixedBufferStream(&data);
    var sieve = BitSieve.init(fbs.reader().any());

    try sieve.refill();
    try std.testing.expect(sieve.bit_count >= 32);
    
    try std.testing.expectEqual(@as(u64, 0xFF), try sieve.readBits(8));
    try std.testing.expectEqual(@as(u64, 0x00), try sieve.readBits(8));
    try std.testing.expectEqual(@as(u64, 0xAA), try sieve.readBits(8));
    try std.testing.expectEqual(@as(u64, 0x55), try sieve.readBits(8));
}
