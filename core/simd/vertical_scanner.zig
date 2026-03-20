const std = @import("std");

pub const FastqScanner = struct {
    pub const ScanResult = struct {
        indices: []usize,
        count: usize,
    };

    /// SIMD-accelerated newline scanner using 32-lane vectors.
    pub fn scanNewlinesSIMD(chunk: []const u8, out: *ScanResult) void {
        out.count = 0;
        const vec_size = 32;
        var i: usize = 0;
        const nl_vec: @Vector(vec_size, u8) = @splat('\n');

        while (i + vec_size <= chunk.len) : (i += vec_size) {
            const v: @Vector(vec_size, u8) = chunk[i..][0..vec_size].*;
            const mask: @Vector(vec_size, bool) = v == nl_vec;
            
            var bitmask = @as(u32, @bitCast(mask));
            while (bitmask != 0) {
                const bit_idx = @ctz(bitmask);
                if (out.count < out.indices.len) {
                    out.indices[out.count] = i + bit_idx;
                    out.count += 1;
                } else return;
                bitmask &= bitmask - 1; // Clear least significant set bit
            }
        }

        // Residual scalar scan
        while (i < chunk.len) : (i += 1) {
            if (chunk[i] == '\n') {
                if (out.count < out.indices.len) {
                    out.indices[out.count] = i;
                    out.count += 1;
                } else return;
            }
        }
    }
};
