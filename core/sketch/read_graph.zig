const std = @import("std");

pub const MinHashSketch = struct {
    hashes: []u32,
    num_hashes: usize,

    pub fn init(allocator: std.mem.Allocator, num_hashes: usize) !MinHashSketch {
        const hashes = try allocator.alloc(u32, num_hashes);
        @memset(hashes, std.math.maxInt(u32));
        return MinHashSketch{
            .hashes = hashes,
            .num_hashes = num_hashes,
        };
    }

    pub fn deinit(self: *MinHashSketch, allocator: std.mem.Allocator) void {
        allocator.free(self.hashes);
    }

    pub fn update(self: *MinHashSketch, kmer_hash: u32) void {
        for (0..self.num_hashes) |i| {
            // Mix the kmer hash with a seed unique to each minhash slot
            const seed = @as(u32, @intCast(i)) *% 0x9e3779b9;
            const h = std.hash.Wyhash.hash(seed, std.mem.asBytes(&kmer_hash));
            const mixed = @as(u32, @truncate(h));
            if (mixed < self.hashes[i]) {
                self.hashes[i] = mixed;
            }
        }
    }

    pub fn similarity(self: *const MinHashSketch, other: *const MinHashSketch) f64 {
        var matches: usize = 0;
        for (0..self.num_hashes) |i| {
            if (self.hashes[i] == other.hashes[i]) {
                matches += 1;
            }
        }
        return @as(f64, @floatFromInt(matches)) / @as(f64, @floatFromInt(self.num_hashes));
    }
};
