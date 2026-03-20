const std = @import("std");

pub fn updateKmerHashes(hashes: anytype, bases: anytype, k: u8) @TypeOf(hashes) {
    const T = @TypeOf(hashes);
    const info = @typeInfo(T);
    const len = info.Vector.len;
    
    const mask = (@as(u32, 1) << @as(u5, @intCast(2 * k))) - 1;
    const mask_vec: T = @splat(mask);
    
    const is_c_u = (bases == @as(@TypeOf(bases), @splat('C')));
    const is_c_l = (bases == @as(@TypeOf(bases), @splat('c')));
    
    const is_g_u = (bases == @as(@TypeOf(bases), @splat('G')));
    const is_g_l = (bases == @as(@TypeOf(bases), @splat('g')));

    const is_t_u = (bases == @as(@TypeOf(bases), @splat('T')));
    const is_t_l = (bases == @as(@TypeOf(bases), @splat('t')));
    
    var bits: T = @splat(0);
    bits = @select(u32, is_c_u, @as(T, @splat(1)), bits);
    bits = @select(u32, is_c_l, @as(T, @splat(1)), bits);
    bits = @select(u32, is_g_u, @as(T, @splat(2)), bits);
    bits = @select(u32, is_g_l, @as(T, @splat(2)), bits);
    bits = @select(u32, is_t_u, @as(T, @splat(3)), bits);
    bits = @select(u32, is_t_l, @as(T, @splat(3)), bits);
    
    const shift_vec: @Vector(len, u5) = @splat(2);
    return ((hashes << shift_vec) | bits) & mask_vec;
}
