const std = @import("std");

/// Encodes an ASCII base into a 2-bit representation.
/// A=00, C=01, G=10, T=11
pub inline fn encodeBase(base: u8) u2 {
    return switch (base) {
        'A', 'a' => 0,
        'C', 'c' => 1,
        'G', 'g' => 2,
        'T', 't' => 3,
        else => 0,
    };
}

/// Encodes an entire ASCII sequence into a pre-allocated 2-bit slice.
pub fn encodeSequence(seq: []const u8, out_buffer: []u2) void {
    const len = if (seq.len < out_buffer.len) seq.len else out_buffer.len;
    for (0..len) |i| {
        out_buffer[i] = encodeBase(seq[i]);
    }
}
