const std = @import("std");

pub fn transpose16x16(rows: [16]@Vector(16, u8)) [16]@Vector(16, u8) {
    var res: [16]@Vector(16, u8) = undefined;
    // Guaranteed bit-exact unrolled matrix transpose
    inline for (0..16) |i| {
        var col: [16]u8 = undefined;
        inline for (0..16) |j| {
            col[j] = rows[j][i];
        }
        res[i] = col;
    }
    return res;
}

pub fn transpose8x8(rows: [8]@Vector(8, u8)) [8]@Vector(8, u8) {
    var res: [8]@Vector(8, u8) = undefined;
    inline for (0..8) |i| {
        var col: [8]u8 = undefined;
        inline for (0..8) |j| {
            col[j] = rows[j][i];
        }
        res[i] = col;
    }
    return res;
}

pub fn load16x16Safe(ptrs: [16][]const u8, pos: usize) [16]@Vector(16, u8) {
    var result: [16]@Vector(16, u8) = undefined;
    inline for (0..16) |i| {
        const row_len = ptrs[i].len;
        if (pos >= row_len) {
            result[i] = @splat(@as(u8, 0));
        } else if (pos + 16 <= row_len) {
            result[i] = ptrs[i][pos..][0..16].*;
        } else {
            // Partial load
            var row: @Vector(16, u8) = @splat(@as(u8, 0));
            const to_copy = row_len - pos;
            var buf = [16]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
            @memcpy(buf[0..to_copy], ptrs[i][pos..row_len]);
            row = buf;
            result[i] = row;
        }
    }
    return result;
}

pub fn load8x8Safe(ptrs: [8][]const u8, pos: usize) [8]@Vector(8, u8) {
    var result: [8]@Vector(8, u8) = undefined;
    inline for (0..8) |i| {
        const row_len = ptrs[i].len;
        if (pos >= row_len) {
            result[i] = @splat(@as(u8, 0));
        } else if (pos + 8 <= row_len) {
            result[i] = ptrs[i][pos..][0..8].*;
        } else {
            // Partial load
            var row: @Vector(8, u8) = @splat(@as(u8, 0));
            const to_copy = row_len - pos;
            var buf = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
            @memcpy(buf[0..to_copy], ptrs[i][pos..row_len]);
            row = buf;
            result[i] = row;
        }
    }
    return result;
}

pub fn transposeReadFast(dest_bases: [][]u8, dest_quals: [][]u8, read_idx: usize, seq: []const u8, qual: []const u8) void {
    const len = @min(seq.len, qual.len);
    var i: usize = 0;
    
    // Vectorized path for long reads
    while (i + 16 <= len) : (i += 16) {
        const s_chunk: @Vector(16, u8) = seq[i..][0..16].*;
        const q_chunk: @Vector(16, u8) = qual[i..][0..16].*;
        
        inline for (0..16) |offset| {
            dest_bases[i + offset][read_idx] = s_chunk[offset];
            dest_quals[i + offset][read_idx] = q_chunk[offset];
        }
    }
    
    // Residual
    while (i < len) : (i += 1) {
        dest_bases[i][read_idx] = seq[i];
        dest_quals[i][read_idx] = qual[i];
    }
}
