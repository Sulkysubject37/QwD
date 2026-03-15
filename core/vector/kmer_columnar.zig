const std = @import("std");

pub fn updateKmerHashes(hashes: anytype, bases: anytype, k: u8) @TypeOf(hashes) {
    const mask = (@as(u32, 1) << @as(u5, @intCast(2 * k))) - 1;
    const mask_vec: @TypeOf(hashes) = @splat(mask);
    
    // Convert ASCII bases to 2-bit in vector
    // A=0, C=1, G=2, T=3
    // Simple mapping: (base >> 1) & 3 works for A,C,G,T (mostly)
    // A: 65 (01000001) -> 32 -> 0
    // C: 67 (01000011) -> 33 -> 1
    // G: 71 (01000111) -> 35 -> 3 (Wait, G should be 2)
    // Let's use a more robust SIMD mapping or just @select
    
    const is_c = bases == @as(@TypeOf(bases), @splat('C')) or bases == @as(@TypeOf(bases), @splat('c'));
    const is_g = bases == @as(@TypeOf(bases), @splat('G')) or bases == @as(@TypeOf(bases), @splat('g'));
    const is_t = bases == @as(@TypeOf(bases), @splat('T')) or bases == @as(@TypeOf(bases), @splat('t'));
    
    var bits: @TypeOf(hashes) = @splat(0);
    bits = @select(u32, is_c, @as(@TypeOf(hashes), @splat(1)), bits);
    bits = @select(u32, is_g, @as(@TypeOf(hashes), @splat(2)), bits);
    bits = @select(u32, is_t, @as(@TypeOf(hashes), @splat(3)), bits);
    
    return ((hashes << @as(u5, 2)) | bits) & mask_vec;
}
