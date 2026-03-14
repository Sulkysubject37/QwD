const std = @import("std");

pub const BloomFilter = struct {
    bits: []u8,
    size_bits: usize,
    hash_count: u8 = 3,

    pub fn init(allocator: std.mem.Allocator, size_bytes: usize) !BloomFilter {
        const bits = try allocator.alloc(u8, size_bytes);
        @memset(bits, 0);
        return BloomFilter{
            .bits = bits,
            .size_bits = size_bytes * 8,
        };
    }

    pub fn deinit(self: *BloomFilter, allocator: std.mem.Allocator) void {
        allocator.free(self.bits);
    }

    pub fn add(self: *BloomFilter, data: []const u8) void {
        const h1 = std.hash.Wyhash.hash(0, data);
        const h2 = std.hash.Wyhash.hash(h1, data);

        for (0..self.hash_count) |i| {
            // Double hashing technique: h(i) = h1 + i * h2
            const combined = h1 +% (i *% h2);
            const bit_idx = combined % self.size_bits;
            self.bits[bit_idx / 8] |= (@as(u8, 1) << @as(u3, @intCast(bit_idx % 8)));
        }
    }

    pub fn contains(self: *const BloomFilter, data: []const u8) bool {
        const h1 = std.hash.Wyhash.hash(0, data);
        const h2 = std.hash.Wyhash.hash(h1, data);

        for (0..self.hash_count) |i| {
            const combined = h1 +% (i *% h2);
            const bit_idx = combined % self.size_bits;
            if ((self.bits[bit_idx / 8] & (@as(u8, 1) << @as(u3, @intCast(bit_idx % 8)))) == 0) {
                return false;
            }
        }
        return true;
    }

    pub fn merge(self: *BloomFilter, other: *const BloomFilter) void {
        for (0..self.bits.len) |i| {
            self.bits[i] |= other.bits[i];
        }
    }
};
