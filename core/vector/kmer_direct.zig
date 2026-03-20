const std = @import("std");

pub fn baseToBits(b: u8) u32 {
    return switch (b) {
        'A', 'a' => 0,
        'C', 'c' => 1,
        'G', 'g' => 2,
        'T', 't' => 3,
        else => 0,
    };
}

/// Updates 8 k-mer hashes simultaneously directly from raw ASCII pointers.
pub fn update8HashesDirect(hashes: *[8]u32, ptrs: [8][]const u8, pos: usize, k: u8) void {
    const mask = (@as(u32, 1) << @as(u5, @intCast(2 * k))) - 1;
    
    inline for (0..8) |i| {
        if (pos < ptrs[i].len) {
            const b = ptrs[i][pos];
            const bits: u32 = switch (b) {
                'A', 'a' => 0,
                'C', 'c' => 1,
                'G', 'g' => 2,
                'T', 't' => 3,
                else => 0,
            };
            hashes[i] = ((hashes[i] << 2) | bits) & mask;
        }
    }
}
