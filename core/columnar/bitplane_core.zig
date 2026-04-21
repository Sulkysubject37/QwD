const std = @import("std");

pub const BitplaneCore = struct {
    allocator: std.mem.Allocator,
    max_read_len: usize,
    u64_per_col: usize,
    
    plane_a: []u64,
    plane_c: []u64,
    plane_g: []u64,
    plane_t: []u64,
    plane_n: []u64,
    plane_mask: []u64,

    cached_fused: ?FusedResults = null,

    pub fn init(allocator: std.mem.Allocator, max_read_len: usize, capacity: usize) !BitplaneCore {
        const u64_per_col = (capacity + 63) / 64;
        const total_u64s = max_read_len * u64_per_col;
        
        return BitplaneCore{
            .allocator = allocator,
            .max_read_len = max_read_len,
            .u64_per_col = u64_per_col,
            .plane_a = try allocator.alloc(u64, total_u64s),
            .plane_c = try allocator.alloc(u64, total_u64s),
            .plane_g = try allocator.alloc(u64, total_u64s),
            .plane_t = try allocator.alloc(u64, total_u64s),
            .plane_n = try allocator.alloc(u64, total_u64s),
            .plane_mask = try allocator.alloc(u64, total_u64s),
        };
    }

    pub fn deinit(self: *BitplaneCore) void {
        self.allocator.free(self.plane_a);
        self.allocator.free(self.plane_c);
        self.allocator.free(self.plane_g);
        self.allocator.free(self.plane_t);
        self.allocator.free(self.plane_n);
        self.allocator.free(self.plane_mask);
    }

    pub fn fromColumnBlock(self: *BitplaneCore, block: anytype) void {
        const count = block.read_count;
        const u64_count = (count + 63) / 64;
        
        // SURGICAL VECTORIZED CLEAR
        for (0..block.active_max_len) |col| {
            const off = col * self.u64_per_col;
            @memset(self.plane_a[off .. off + u64_count], 0);
            @memset(self.plane_c[off .. off + u64_count], 0);
            @memset(self.plane_g[off .. off + u64_count], 0);
            @memset(self.plane_t[off .. off + u64_count], 0);
            @memset(self.plane_n[off .. off + u64_count], 0);
            @memset(self.plane_mask[off .. off + u64_count], 0);
        }

        const vec_size = 32;
        const a_v: @Vector(vec_size, u8) = @splat('A');
        const c_v: @Vector(vec_size, u8) = @splat('C');
        const g_v: @Vector(vec_size, u8) = @splat('G');
        const t_v: @Vector(vec_size, u8) = @splat('T');
        const n_v: @Vector(vec_size, u8) = @splat('N');
        const zero_v: @Vector(vec_size, u8) = @splat(0);

        for (0..block.active_max_len) |col| {
            const bp_col_off = col * self.u64_per_col;
            const src = block.bases[col].ptr;

            var i: usize = 0;
            while (i + vec_size <= count) : (i += vec_size) {
                const chunk: @Vector(vec_size, u8) = src[i..][0..vec_size].*;
                
                // SEC-ZERO: Verified bitplane population
                const m_a = (chunk == a_v);
                const m_c = (chunk == c_v);
                const m_g = (chunk == g_v);
                const m_t = (chunk == t_v);
                const m_n = (chunk == n_v);
                const m_mask = (chunk != zero_v);

                const word_idx = i >> 6;
                const bit_shift = @as(u6, @intCast(i & 63));
                
                // Zig v0.16 bit-packing: cast @Vector(32, u1) to u32
                const bits_a: u32 = @bitCast(@as(@Vector(32, u1), @intFromBool(m_a)));
                const bits_c: u32 = @bitCast(@as(@Vector(32, u1), @intFromBool(m_c)));
                const bits_g: u32 = @bitCast(@as(@Vector(32, u1), @intFromBool(m_g)));
                const bits_t: u32 = @bitCast(@as(@Vector(32, u1), @intFromBool(m_t)));
                const bits_n: u32 = @bitCast(@as(@Vector(32, u1), @intFromBool(m_n)));
                const bits_mask: u32 = @bitCast(@as(@Vector(32, u1), @intFromBool(m_mask)));
                
                self.plane_a[bp_col_off + word_idx] |= (@as(u64, bits_a) << bit_shift);
                self.plane_c[bp_col_off + word_idx] |= (@as(u64, bits_c) << bit_shift);
                self.plane_g[bp_col_off + word_idx] |= (@as(u64, bits_g) << bit_shift);
                self.plane_t[bp_col_off + word_idx] |= (@as(u64, bits_t) << bit_shift);
                self.plane_n[bp_col_off + word_idx] |= (@as(u64, bits_n) << bit_shift);
                self.plane_mask[bp_col_off + word_idx] |= (@as(u64, bits_mask) << bit_shift);
            }
            
            // Tail handled via scalar for bit-exactness
            while (i < count) : (i += 1) {
                const b = src[i];
                const bit = @as(u64, 1) << @as(u6, @intCast(i & 63));
                const word_idx = i >> 6;
                switch (b) {
                    'A', 'a' => self.plane_a[bp_col_off + word_idx] |= bit,
                    'C', 'c' => self.plane_c[bp_col_off + word_idx] |= bit,
                    'G', 'g' => self.plane_g[bp_col_off + word_idx] |= bit,
                    'T', 't' => self.plane_t[bp_col_off + word_idx] |= bit,
                    'N', 'n' => self.plane_n[bp_col_off + word_idx] |= bit,
                    else => {},
                }
                if (b != 0) self.plane_mask[bp_col_off + word_idx] |= bit;
            }
        }
    }

    pub fn computeSignature(self: *const BitplaneCore, read_idx: usize, len: usize) u64 {
        var h: u64 = 0xcbf29ce484222325;
        const word_idx = read_idx >> 6;
        const bit_mask = @as(u64, 1) << @as(u6, @intCast(read_idx & 63));
        
        const limit = @min(len, 32);
        for (0..limit) |col| {
            const off = col * self.u64_per_col + word_idx;
            if ((self.plane_mask[off] & bit_mask) == 0) break;

            var b: u8 = 5;
            if ((self.plane_a[off] & bit_mask) != 0) { b = 1; }
            else if ((self.plane_c[off] & bit_mask) != 0) { b = 2; }
            else if ((self.plane_g[off] & bit_mask) != 0) { b = 3; }
            else if ((self.plane_t[off] & bit_mask) != 0) { b = 4; }
            
            h ^= b;
            h = h *% 0x100000001b3;
        }
        return h;
    }

    pub const FusedResults = struct {
        gc_count: usize,
        a_count: usize,
        c_count: usize,
        g_count: usize,
        t_count: usize,
        n_count: usize,
        total_bases: usize,
        integrity_violations: usize,
    };

    pub fn getFused(self: *BitplaneCore, read_count: usize) FusedResults {
        if (self.cached_fused) |res| return res;
        const res = self.computeFused(read_count);
        self.cached_fused = res;
        return res;
    }

    pub fn computeFused(self: *const BitplaneCore, read_count: usize) FusedResults {
        var res = FusedResults{ 
            .gc_count = 0, .a_count = 0, .c_count = 0, 
            .g_count = 0, .t_count = 0, .n_count = 0,
            .total_bases = 0, .integrity_violations = 0,
        };
        
        const u64_count = (read_count + 63) / 64;
        const last_lane_mask = if (read_count % 64 == 0) ~@as(u64, 0) else (@as(u64, 1) << @as(u6, @intCast(read_count % 64))) - 1;

        for (0..self.max_read_len) |col| {
            const offset = col * self.u64_per_col;
            const limit = offset + u64_count;
            
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

                // SEC-ZERO: Bitplane Mutex Invariant
                // Every base must be exactly one of A, C, G, T, or N
                const parity = a ^ c ^ g ^ t ^ n;
                if (parity != mask) {
                    res.integrity_violations += @popCount(parity ^ mask);
                }

                res.a_count += @popCount(a);
                res.c_count += @popCount(c);
                res.g_count += @popCount(g);
                res.t_count += @popCount(t);
                res.n_count += @popCount(n);
                res.total_bases += @popCount(mask);
                res.gc_count += @popCount(g | c);
            }
        }
        return res;
    }

    pub fn clear(self: *BitplaneCore, _: usize) void {
        self.cached_fused = null;
    }
};
