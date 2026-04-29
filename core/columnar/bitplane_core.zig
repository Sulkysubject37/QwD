const std = @import("std");

/// High-Performance Bitplane Engine
/// Enforces O(1) bitwise genomics across 1024-read lanes
pub const BitplaneCore = struct {
    allocator: std.mem.Allocator,
    max_read_len: usize,
    u64_per_col: usize,
    
    // Bitplanes
    plane_a: []u64,
    plane_c: []u64,
    plane_g: []u64,
    plane_t: []u64,
    plane_n: []u64,
    plane_mask: []u64,
    
    cached_fused: ?FusedResults = null,

    pub fn init(allocator: std.mem.Allocator, max_read_len: usize, lane_width: usize) !BitplaneCore {
        const u64_per_col = (lane_width + 63) / 64;
        const total_u64 = max_read_len * u64_per_col;
        
        var self = BitplaneCore{
            .allocator = allocator,
            .max_read_len = max_read_len,
            .u64_per_col = u64_per_col,
            .plane_a = try allocator.alloc(u64, total_u64),
            .plane_c = try allocator.alloc(u64, total_u64),
            .plane_g = try allocator.alloc(u64, total_u64),
            .plane_t = try allocator.alloc(u64, total_u64),
            .plane_n = try allocator.alloc(u64, total_u64),
            .plane_mask = try allocator.alloc(u64, total_u64),
        };
        self.clearAll();
        return self;
    }

    pub fn deinit(self: *BitplaneCore) void {
        self.allocator.free(self.plane_a);
        self.allocator.free(self.plane_c);
        self.allocator.free(self.plane_g);
        self.allocator.free(self.plane_t);
        self.allocator.free(self.plane_n);
        self.allocator.free(self.plane_mask);
    }

    pub fn clearAll(self: *BitplaneCore) void {
        @memset(self.plane_a, 0);
        @memset(self.plane_c, 0);
        @memset(self.plane_g, 0);
        @memset(self.plane_t, 0);
        @memset(self.plane_n, 0);
        @memset(self.plane_mask, 0);
        self.cached_fused = null;
    }

    pub fn fromColumnBlock(self: *BitplaneCore, block: anytype) void {
        self.clearAll();
        const count = block.read_count;
        const max_len = @min(block.active_max_len, self.max_read_len);
        
        for (0..max_len) |col| {
            const offset = col * self.u64_per_col;
            for (0..count) |read_idx| {
                const u64_idx = read_idx / 64;
                const bit_idx: u6 = @intCast(read_idx % 64);
                const bit = @as(u64, 1) << bit_idx;
                
                const base = block.bases[col][read_idx];
                self.plane_mask[offset + u64_idx] |= bit;
                
                switch (base) {
                    'A', 'a' => self.plane_a[offset + u64_idx] |= bit,
                    'C', 'c' => self.plane_c[offset + u64_idx] |= bit,
                    'G', 'g' => self.plane_g[offset + u64_idx] |= bit,
                    'T', 't' => self.plane_t[offset + u64_idx] |= bit,
                    else => self.plane_n[offset + u64_idx] |= bit,
                }
            }
        }
    }

    pub const FusedResults = struct {
        gc_count: usize = 0,
        a_count: usize = 0,
        c_count: usize = 0,
        g_count: usize = 0,
        t_count: usize = 0,
        n_count: usize = 0,
        total_bases: usize = 0,
        integrity_violations: usize = 0,
        per_read_gc: [1024]u16 = [_]u16{0} ** 1024,
    };

    pub fn computeFusedInto(self: *const BitplaneCore, read_count: usize, res: *FusedResults) void {
        const u64_count = (read_count + 63) / 64;
        const last_lane_mask = if (read_count % 64 == 0) ~@as(u64, 0) else (@as(u64, 1) << @as(u6, @intCast(read_count % 64))) - 1;

        for (0..self.max_read_len) |col| {
            const offset = col * self.u64_per_col;
            const limit = @min(offset + u64_count, self.plane_mask.len);
            if (offset >= self.plane_mask.len) break;
            
            var any_active: u64 = 0;
            for (offset..limit) |idx| any_active |= self.plane_mask[idx];
            if (any_active == 0) break;

            for (offset..limit) |idx| {
                const a = self.plane_a[idx];
                const c = self.plane_c[idx];
                const g = self.plane_g[idx];
                const t = self.plane_t[idx];
                const n = self.plane_n[idx];
                var mask = self.plane_mask[idx];

                if (idx == limit - 1) mask &= last_lane_mask;

                res.a_count += @popCount(a & mask);
                res.c_count += @popCount(c & mask);
                res.g_count += @popCount(g & mask);
                res.t_count += @popCount(t & mask);
                res.n_count += @popCount(n & mask);

                // Per-read GC counts
                const gc_mask = (g | c) & mask;
                if (gc_mask != 0) {
                    var m = gc_mask;
                    const base_read_idx = (idx - offset) * 64;
                    while (m != 0) {
                        const bit_idx = @ctz(m);
                        const read_idx = base_read_idx + bit_idx;
                        if (read_idx < 1024) res.per_read_gc[read_idx] += 1;
                        m &= m - 1;
                    }
                }
            }
        }
        res.gc_count = res.g_count + res.c_count;
        res.total_bases = res.a_count + res.c_count + res.g_count + res.t_count + res.n_count;
    }
    
    pub fn computeSignature(self: *const BitplaneCore, read_idx: usize, len: usize) u64 {
        var hash: u64 = 0x811C9DC5;
        const u64_idx = read_idx / 64;
        const bit_idx: u6 = @intCast(read_idx % 64);
        const bit_mask = @as(u64, 1) << bit_idx;

        for (0..len) |col| {
            const offset = col * self.u64_per_col + u64_idx;
            if (offset >= self.plane_a.len) break;
            var val: u8 = 0;
            if ((self.plane_a[offset] & bit_mask) != 0) { val = 'A'; }
            else if ((self.plane_c[offset] & bit_mask) != 0) { val = 'C'; }
            else if ((self.plane_g[offset] & bit_mask) != 0) { val = 'G'; }
            else if ((self.plane_t[offset] & bit_mask) != 0) { val = 'T'; }
            else { val = 'N'; }
            
            hash = (hash ^ val) *% 0x01000193;
        }
        return hash;
    }
};
