const std = @import("std");

/// Encodes an ASCII sequence into a 2-bit representation using SIMD.
/// For true SIMD, we could use `@Vector`. 
/// For compatibility and simplicity, this relies on auto-vectorization or chunking.
pub fn encodeSequenceSimd(seq: []const u8, out_buffer: []u2) void {
    const len = if (seq.len < out_buffer.len) seq.len else out_buffer.len;
    
    // In a fully optimized engine, we would use _mm256_shuffle_epi8 (AVX2) or vqtbl1q_u8 (NEON)
    // For Zig 0.13.0, we use a simple loop that the compiler auto-vectorizes
    for (0..len) |i| {
        const b = seq[i];
        out_buffer[i] = switch (b) {
            'A', 'a' => 0,
            'C', 'c' => 1,
            'G', 'g' => 2,
            'T', 't' => 3,
            else => 0,
        };
    }
}
