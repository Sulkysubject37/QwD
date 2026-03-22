const std = @import("std");
const simd_transpose = @import("simd_transpose");

pub const FastqColumnBlock = struct {
    // bases[pos][read_index] - Flat-mapped for cache locality
    bases: [][]u8,
    qualities: [][]u8,
    read_lengths: []u16,
    read_count: usize,
    max_read_len: usize,
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
        self.read_count = 0;
    }

    pub fn transposeFromIndices(self: *FastqColumnBlock, data: []const u8, indices: []const usize, start_nl: i64, count: usize) void {
        self.read_count = count;
        
        var read_idx: usize = 0;
        while (read_idx + 8 <= count) : (read_idx += 8) {
            var b_ptrs: [8][]const u8 = undefined;
            var q_ptrs: [8][]const u8 = undefined;
            inline for (0..8) |i| {
                const r_idx = @as(i64, @intCast(read_idx + i));
                const current_nl = start_nl + r_idx * 4;
                
                const seq_start = indices[@intCast(current_nl + 1)] + 1;
                var seq_end = indices[@intCast(current_nl + 2)];
                const qual_start = indices[@intCast(current_nl + 3)] + 1;
                var qual_end = indices[@intCast(current_nl + 4)];

                // Strip trailing \r if present (CRLF support)
                if (seq_end > seq_start and data[seq_end - 1] == '\r') seq_end -= 1;
                if (qual_end > qual_start and data[qual_end - 1] == '\r') qual_end -= 1;
                
                const seq_len = seq_end - seq_start;
                
                b_ptrs[i] = data[seq_start..seq_end];
                q_ptrs[i] = data[qual_start..qual_end];
                self.read_lengths[read_idx + i] = @intCast(seq_len);

                // Zero out tails for the current read in the block to prevent leakage
                for (seq_len..self.max_read_len) |pos| {
                   self.bases[pos][read_idx + i] = 0;
                   self.qualities[pos][read_idx + i] = 0;
                }
            }
            
            var pos: usize = 0;
            while (pos < self.max_read_len) : (pos += 8) {
                const b_rows = simd_transpose.load8x8Safe(b_ptrs, pos);
                const transposed_b = simd_transpose.transpose8x8(b_rows);
                inline for (0..8) |i| {
                    if (pos + i < self.max_read_len) {
                        const dest_col = self.bases[pos + i];
                        const chunk: [8]u8 = @bitCast(transposed_b[i]);
                        @memcpy(dest_col[read_idx..read_idx+8], &chunk);
                    }
                }

                const q_rows = simd_transpose.load8x8Safe(q_ptrs, pos);
                const transposed_q = simd_transpose.transpose8x8(q_rows);
                inline for (0..8) |i| {
                    if (pos + i < self.max_read_len) {
                        const dest_col = self.qualities[pos + i];
                        const chunk: [8]u8 = @bitCast(transposed_q[i]);
                        @memcpy(dest_col[read_idx..read_idx+8], &chunk);
                    }
                }
            }
        }

        // Residual reads handling
        while (read_idx < count) : (read_idx += 1) {
            const r_idx = @as(i64, @intCast(read_idx));
            const current_nl = start_nl + r_idx * 4;
            
            const seq_start = indices[@intCast(current_nl + 1)] + 1;
            var seq_end = indices[@intCast(current_nl + 2)];
            const qual_start = indices[@intCast(current_nl + 3)] + 1;
            var qual_end = indices[@intCast(current_nl + 4)];

            // Strip trailing \r if present (CRLF support)
            if (seq_end > seq_start and data[seq_end - 1] == '\r') seq_end -= 1;
            if (qual_end > qual_start and data[qual_end - 1] == '\r') qual_end -= 1;
            
            const seq = data[seq_start..seq_end];
            const qual = data[qual_start..qual_end];
            const len = @min(seq.len, self.max_read_len);
            for (0..len) |pos| {
                self.bases[pos][read_idx] = seq[pos];
                self.qualities[pos][read_idx] = qual[pos];
            }
            // Zero out remainder of columns for this read to prevent leakage
            for (len..self.max_read_len) |pos| {
                self.bases[pos][read_idx] = 0;
                self.qualities[pos][read_idx] = 0;
            }
            self.read_lengths[read_idx] = @intCast(len);
        }
    }
};
