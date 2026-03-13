const std = @import("std");

/// Rolling Bit-Hash for k-mers.
/// `hash` is the previous k-mer hash.
/// `next_base` is the 2-bit encoded incoming base.
/// `k` is the k-mer length.
pub inline fn rollKmer(hash: usize, next_base: u2, k: u8) usize {
    const mask = (@as(usize, 1) << @as(u6, @intCast(2 * k))) - 1;
    return ((hash << 2) | next_base) & mask;
}
