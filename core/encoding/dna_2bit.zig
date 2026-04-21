const std = @import("std");

/// SIMD-Accelerated 2-bit DNA Encoding (Phase S)
/// Maps: 'A' -> 00, 'C' -> 01, 'G' -> 10, 'T' -> 11
/// Handles lowercase ('a','c','g','t') and 'N' (maps to 0, breaks validity)

pub fn encodeChunk(ascii: @Vector(32, u8)) struct { val: @Vector(32, u8), valid: @Vector(32, u8) } {
    // 1. Normalize ASCII (mask with 0x1F maps 'A' and 'a' to the same index)
    const v_idx = ascii & @as(@Vector(32, u8), @splat(0x1F));
    
    // 2. Encoding Lookup Table (Indices 1, 3, 7, 20 are A, C, G, T)
    const encoding_lut: @Vector(32, u8) = .{
        0, 0, 0, 1, 0, 0, 0, 2, // 1='A'->0, 3='C'->1, 7='G'->2
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 3, 0, 0, 0, // 20='T'->3
        0, 0, 0, 0, 0, 0, 0, 0,
    };
    
    // 3. Validity Lookup Table (Only A, C, G, T are valid)
    const validity_lut: @Vector(32, u8) = .{
        0, 1, 0, 1, 0, 0, 0, 1, // 1, 3, 7 are valid
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 1, 0, 0, 0, // 20 is valid
        0, 0, 0, 0, 0, 0, 0, 0,
    };

    // Note: Zig v0.16 @shuffle requires i32 indices.
    const indices: @Vector(32, i32) = @intCast(v_idx);
    
    return .{
        .val = @shuffle(u8, encoding_lut, undefined, indices),
        .valid = @shuffle(u8, validity_lut, undefined, indices),
    };
}

pub fn encodeSequenceScalar(seq: []const u8, out: []u8) usize {
    for (seq, 0..) |b, i| {
        out[i] = switch (b) {
            'A', 'a' => 0,
            'C', 'c' => 1,
            'G', 'g' => 2,
            'T', 't' => 3,
            else => 0,
        };
    }
    return seq.len;
}
