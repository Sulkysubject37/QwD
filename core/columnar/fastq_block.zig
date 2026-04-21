const std = @import("std");
const simd_transpose = @import("simd_transpose");
const parser = @import("parser");

pub const FastqColumnBlock = struct {
    bases: [][]u8,
    qualities: [][]u8,
    read_lengths: []u16,
    read_count: usize,
    max_read_len: usize, 
    active_max_len: usize,
    capacity: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize, max_read_len: usize) !FastqColumnBlock {
        var bases = try allocator.alloc([]u8, max_read_len);
        var qualities = try allocator.alloc([]u8, max_read_len);
        
        const total_size = max_read_len * capacity;
        const base_buf = try allocator.alloc(u8, total_size);
        const qual_buf = try allocator.alloc(u8, total_size);
        
        @memset(base_buf, 0);
        @memset(qual_buf, 0);

        for (0..max_read_len) |i| {
            bases[i] = base_buf[i * capacity .. (i + 1) * capacity];
            qualities[i] = qual_buf[i * capacity .. (i + 1) * capacity];
        }

        return FastqColumnBlock{
            .bases = bases,
            .qualities = qualities,
            .read_lengths = try allocator.alloc(u16, capacity),
            .read_count = 0,
            .max_read_len = max_read_len,
            .active_max_len = 0,
            .capacity = capacity,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FastqColumnBlock) void {
        self.allocator.free(self.bases[0].ptr[0 .. self.max_read_len * self.capacity]);
        self.allocator.free(self.qualities[0].ptr[0 .. self.max_read_len * self.capacity]);
        self.allocator.free(self.bases);
        self.allocator.free(self.qualities);
        self.allocator.free(self.read_lengths);
    }

    pub fn clear(self: *FastqColumnBlock) void {
        // SURGICAL RESET: only reset active memory range to maintain peak speed.
        const total_bytes = self.active_max_len * self.capacity;
        if (total_bytes > 0) {
            @memset(self.bases[0].ptr[0..total_bytes], 0);
            @memset(self.qualities[0].ptr[0..total_bytes], 0);
        }
        @memset(self.read_lengths[0..self.read_count], 0);
        self.read_count = 0;
        self.active_max_len = 0;
    }

    pub fn transposeFromIndices(self: *FastqColumnBlock, data: []const u8, indices: []const usize, start_nl_idx: usize, count: usize) void {
        self.read_count = count;
        var batch_max_len: usize = 0;

        // Pass 1: SIMD 16-read blocks
        var i: usize = 0;
        while (i + 16 <= count) : (i += 16) {
            var b_ptrs: [16][]const u8 = undefined;
            var q_ptrs: [16][]const u8 = undefined;
            var local_max: usize = 0;

            inline for (0..16) |j| {
                const idx_base = start_nl_idx + (i + j) * 4;
                const seq_start = indices[idx_base] + 1;
                const seq_end = indices[idx_base + 1];
                const qual_start = indices[idx_base + 2] + 1;
                const qual_end = indices[idx_base + 3];
                
                const seq_len = seq_end - seq_start;
                const qual_len = qual_end - qual_start;
                const len = @min(@min(seq_len, qual_len), self.max_read_len);

                b_ptrs[j] = data[seq_start .. seq_start + len];
                q_ptrs[j] = data[qual_start .. qual_start + len];
                self.read_lengths[i + j] = @intCast(len);
                if (len > local_max) local_max = len;
            }
            if (local_max > batch_max_len) batch_max_len = local_max;

            var pos: usize = 0;
            while (pos + 16 <= local_max) : (pos += 16) {
                const b_rows = simd_transpose.load16x16Safe(b_ptrs, pos);
                const transposed_b = simd_transpose.transpose16x16(b_rows);
                inline for (0..16) |trans_idx| {
                    const chunk: [16]u8 = @bitCast(transposed_b[trans_idx]);
                    @memcpy(self.bases[pos + trans_idx][i..][0..16], &chunk);
                }
                const q_rows = simd_transpose.load16x16Safe(q_ptrs, pos);
                const transposed_q = simd_transpose.transpose16x16(q_rows);
                inline for (0..16) |trans_idx| {
                    const chunk: [16]u8 = @bitCast(transposed_q[trans_idx]);
                    @memcpy(self.qualities[pos + trans_idx][i..][0..16], &chunk);
                }
            }
            // Residual scalar for the 16-read batch
            while (pos < local_max) : (pos += 1) {
                inline for (0..16) |j| {
                    if (pos < b_ptrs[j].len) {
                        self.bases[pos][i + j] = b_ptrs[j][pos];
                        self.qualities[pos][i + j] = q_ptrs[j][pos];
                    }
                }
            }
        }

        // Pass 2: Handle remaining reads
        while (i < count) : (i += 1) {
            const idx_base = start_nl_idx + i * 4;
            const seq_start = indices[idx_base] + 1;
            const seq_end = indices[idx_base + 1];
            const qual_start = indices[idx_base + 2] + 1;
            const qual_end = indices[idx_base + 3];
            const len = @min(@min(seq_end - seq_start, qual_end - qual_start), self.max_read_len);
            
            for (0..len) |pos| {
                self.bases[pos][i] = data[seq_start + pos];
                self.qualities[pos][i] = data[qual_start + pos];
            }
            self.read_lengths[i] = @intCast(len);
            if (len > batch_max_len) batch_max_len = len;
        }
        self.active_max_len = batch_max_len;
    }

    pub fn getReadRaw(self: *const FastqColumnBlock, idx: usize, allocator: std.mem.Allocator) struct { seq: []u8, qual: []u8 } {
        const len = self.read_lengths[idx];
        const seq = allocator.alloc(u8, len) catch unreachable;
        const qual = allocator.alloc(u8, len) catch unreachable;
        for (0..len) |pos| {
            seq[pos] = self.bases[pos][idx];
            qual[pos] = self.qualities[pos][idx];
        }
        return .{ .seq = seq, .qual = qual };
    }
};
