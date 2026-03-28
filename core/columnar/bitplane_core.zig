const std = @import("std");

pub const BitplaneCore = struct {
    plane_a: []u64,
    plane_c: []u64,
    plane_g: []u64,
    plane_t: []u64,
    plane_n: []u64,
    plane_mask: []u64, // 1 for any valid base position
    read_count: usize,
    max_read_len: usize,
    u64_per_col: usize,
    allocator: std.mem.Allocator,
    cached_fused: ?FusedResults = null,

    pub fn init(allocator: std.mem.Allocator, capacity: usize, max_read_len: usize) !BitplaneCore {
        const u64_per_col = (capacity + 63) / 64;
        const total_u64s = u64_per_col * max_read_len;
        
        return BitplaneCore{
            .plane_a = try allocator.alloc(u64, total_u64s),
            .plane_c = try allocator.alloc(u64, total_u64s),
            .plane_g = try allocator.alloc(u64, total_u64s),
            .plane_t = try allocator.alloc(u64, total_u64s),
            .plane_n = try allocator.alloc(u64, total_u64s),
            .plane_mask = try allocator.alloc(u64, total_u64s),
            .read_count = capacity,
            .max_read_len = max_read_len,
            .u64_per_col = u64_per_col,
            .allocator = allocator,
            .cached_fused = null,
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
        self.clear(count);
        
        const vec_size = 32;
        const a_vec: @Vector(vec_size, u8) = @splat('A');
        const c_vec: @Vector(vec_size, u8) = @splat('C');
        const g_vec: @Vector(vec_size, u8) = @splat('G');
        const t_vec: @Vector(vec_size, u8) = @splat('T');
        const al_vec: @Vector(vec_size, u8) = @splat('a');
        const cl_vec: @Vector(vec_size, u8) = @splat('c');
        const gl_vec: @Vector(vec_size, u8) = @splat('g');
        const tl_vec: @Vector(vec_size, u8) = @splat('t');
        const n_vec: @Vector(vec_size, u8) = @splat('N');
        const nl_vec: @Vector(vec_size, u8) = @splat('n');
        const ones: @Vector(vec_size, u8) = @splat(1);
        const zeros_u8: @Vector(vec_size, u8) = @splat(0);

        for (0..self.max_read_len) |col| {
            const col_offset = col * self.u64_per_col;
            const base_col = block.bases[col];
            var read_idx: usize = 0;

            while (read_idx + vec_size <= count) : (read_idx += vec_size) {
                const v: @Vector(vec_size, u8) = base_col[read_idx..][0..vec_size].*;

                const mask_a = @select(u8, v == a_vec, ones, zeros_u8) | @select(u8, v == al_vec, ones, zeros_u8);
                const mask_c = @select(u8, v == c_vec, ones, zeros_u8) | @select(u8, v == cl_vec, ones, zeros_u8);
                const mask_g = @select(u8, v == g_vec, ones, zeros_u8) | @select(u8, v == gl_vec, ones, zeros_u8);
                const mask_t = @select(u8, v == t_vec, ones, zeros_u8) | @select(u8, v == tl_vec, ones, zeros_u8);
                const mask_n = @select(u8, v == n_vec, ones, zeros_u8) | @select(u8, v == nl_vec, ones, zeros_u8);
                
                const bits_a = @as(u32, @bitCast(mask_a != zeros_u8));
                const bits_c = @as(u32, @bitCast(mask_c != zeros_u8));
                const bits_g = @as(u32, @bitCast(mask_g != zeros_u8));
                const bits_t = @as(u32, @bitCast(mask_t != zeros_u8));
                const bits_n = @as(u32, @bitCast(mask_n != zeros_u8));

                const word_idx = read_idx >> 6;
                const shift: u6 = @intCast(read_idx & 63);
                
                self.plane_a[col_offset + word_idx] |= @as(u64, bits_a) << shift;
                self.plane_c[col_offset + word_idx] |= @as(u64, bits_c) << shift;
                self.plane_g[col_offset + word_idx] |= @as(u64, bits_g) << shift;
                self.plane_t[col_offset + word_idx] |= @as(u64, bits_t) << shift;
                self.plane_n[col_offset + word_idx] |= @as(u64, bits_n) << shift;
                self.plane_mask[col_offset + word_idx] |= @as(u64, @as(u32, @bitCast(v != zeros_u8))) << shift;
            }

            // Residual scalar population
            while (read_idx < count) : (read_idx += 1) {
                const b = base_col[read_idx];
                const word_idx = read_idx >> 6;
                const bit = @as(u64, 1) << @as(u6, @intCast(read_idx & 63));
                
                if (b != 0) {
                    self.plane_mask[col_offset + word_idx] |= bit;
                    switch (b) {
                        'A', 'a' => self.plane_a[col_offset + word_idx] |= bit,
                        'C', 'c' => self.plane_c[col_offset + word_idx] |= bit,
                        'G', 'g' => self.plane_g[col_offset + word_idx] |= bit,
                        'T', 't' => self.plane_t[col_offset + word_idx] |= bit,
                        'N', 'n' => self.plane_n[col_offset + word_idx] |= bit,
                        else => {},
                    }
                }
            }
        }
    }

    pub fn clear(self: *BitplaneCore, count: usize) void {
        const u64_count = (count + 63) / 64;
        self.cached_fused = null;
        for (0..self.max_read_len) |col| {
            const offset = col * self.u64_per_col;
            @memset(self.plane_a[offset .. offset + u64_count], 0);
            @memset(self.plane_c[offset .. offset + u64_count], 0);
            @memset(self.plane_g[offset .. offset + u64_count], 0);
            @memset(self.plane_t[offset .. offset + u64_count], 0);
            @memset(self.plane_n[offset .. offset + u64_count], 0);
            @memset(self.plane_mask[offset .. offset + u64_count], 0);
        }
    }

    /// Fused Analytics: Count everything in one bitwise pass
    pub const FusedResults = struct {
        gc_count: usize,
        a_count: usize,
        c_count: usize,
        g_count: usize,
        t_count: usize,
        n_count: usize,
        total_bases: usize,
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
            .total_bases = 0 
        };
        _ = read_count;

        for (0..self.plane_a.len) |i| {
            res.a_count += @popCount(self.plane_a[i]);
            res.c_count += @popCount(self.plane_c[i]);
            res.g_count += @popCount(self.plane_g[i]);
            res.t_count += @popCount(self.plane_t[i]);
            res.n_count += @popCount(self.plane_n[i]);
            res.total_bases += @popCount(self.plane_mask[i]);
            res.gc_count += @popCount(self.plane_g[i] | self.plane_c[i]);
        }
        return res;
    }
};
