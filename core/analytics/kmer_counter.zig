const std = @import("std");

pub const KmerCounter = struct {
    counts: []u32,
    k: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, k: usize) !KmerCounter {
        const size = @as(usize, 1) << (@as(u6, @intCast(k)) * 2);
        const counts = try allocator.alloc(u32, size);
        @memset(counts, 0);
        return KmerCounter{
            .counts = counts,
            .k = k,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *KmerCounter) void {
        self.allocator.free(self.counts);
    }

    pub fn add(self: *KmerCounter, packed_kmer: u64) void {
        const mask = (@as(u64, 1) << (@as(u6, @intCast(self.k)) * 2)) - 1;
        const idx = packed_kmer & mask;
        self.counts[idx] = self.counts[idx] +% 1;
    }

    pub fn addWord(self: *KmerCounter, packed_kmers: [64]u64) void {
        const mask = (@as(u64, 1) << (@as(u6, @intCast(self.k)) * 2)) - 1;
        for (packed_kmers) |pk| {
            if (pk == 0xFFFFFFFFFFFFFFFF) continue; // Skip invalid
            const idx = pk & mask;
            self.counts[idx] = self.counts[idx] +% 1;
        }
    }

    pub fn merge(self: *KmerCounter, other: *const KmerCounter) void {
        for (self.counts, 0..) |*count, i| {
            count.* = count.* +% other.counts[i];
        }
    }
    
    pub fn getTop(self: *const KmerCounter, top: []usize) void {
        @memset(top, 0);
        for (self.counts) |count| {
            if (count > top[0]) {
                top[2] = top[1];
                top[1] = top[0];
                top[0] = count;
            } else if (count > top[1]) {
                top[2] = top[1];
                top[1] = count;
            } else if (count > top[2]) {
                top[2] = count;
            }
        }
    }
};
