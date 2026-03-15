const std = @import("std");

pub const Bitplanes = struct {
    plane_a: []u64,
    plane_c: []u64,
    plane_g: []u64,
    plane_t: []u64,
    read_count: usize,
    max_read_len: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize, max_read_len: usize) !Bitplanes {
        // capacity must be multiple of 64
        const u64_count = (capacity + 63) / 64;
        const total_u64s = u64_count * max_read_len;
        
        return Bitplanes{
            .plane_a = try allocator.alloc(u64, total_u64s),
            .plane_c = try allocator.alloc(u64, total_u64s),
            .plane_g = try allocator.alloc(u64, total_u64s),
            .plane_t = try allocator.alloc(u64, total_u64s),
            .read_count = capacity,
            .max_read_len = max_read_len,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Bitplanes) void {
        self.allocator.free(self.plane_a);
        self.allocator.free(self.plane_c);
        self.allocator.free(self.plane_g);
        self.allocator.free(self.plane_t);
    }

    pub fn reset(self: *Bitplanes) void {
        @memset(self.plane_a, 0);
        @memset(self.plane_c, 0);
        @memset(self.plane_g, 0);
        @memset(self.plane_t, 0);
    }

    pub fn fromColumnBlock(self: *Bitplanes, block: anytype) void {
        self.reset();
        const u64_per_col = (block.capacity + 63) / 64;
        
        for (0..block.max_read_len) |col| {
            const col_offset = col * u64_per_col;
            for (0..block.read_count) |read_idx| {
                const b = block.bases[col][read_idx];
                const word_idx = read_idx / 64;
                const bit_idx = @as(u6, @intCast(read_idx % 64));
                const bit = @as(u64, 1) << bit_idx;
                
                switch (b) {
                    'A', 'a' => self.plane_a[col_offset + word_idx] |= bit,
                    'C', 'c' => self.plane_c[col_offset + word_idx] |= bit,
                    'G', 'g' => self.plane_g[col_offset + word_idx] |= bit,
                    'T', 't' => self.plane_t[col_offset + word_idx] |= bit,
                    else => {},
                }
            }
        }
    }

    pub fn countGc(self: *const Bitplanes) usize {
        var total: usize = 0;
        for (0..self.plane_g.len) |i| {
            total += @popCount(self.plane_g[i] | self.plane_c[i]);
        }
        return total;
    }
};
