const std = @import("std");

/// Transposes an 16x16 matrix of bytes using register shuffles.
pub fn transpose16x16(rows: [16]@Vector(16, u8)) [16]@Vector(16, u8) {
    var s1: [16]@Vector(16, u8) = undefined;
    inline for (0..8) |i| {
        s1[i*2] = @shuffle(u8, rows[i*2], rows[i*2+1], [16]i32{ 0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5, -6, 6, -7, 7, -8 });
        s1[i*2+1] = @shuffle(u8, rows[i*2], rows[i*2+1], [16]i32{ 8, -9, 9, -10, 10, -11, 11, -12, 12, -13, 13, -14, 14, -15, 15, -16 });
    }

    var s2: [16]@Vector(8, u16) = undefined;
    inline for (0..4) |i| {
        const v0: @Vector(8, u16) = @bitCast(s1[i*4]);
        const v1: @Vector(8, u16) = @bitCast(s1[i*4+2]);
        s2[i*4] = @shuffle(u16, v0, v1, [8]i32{ 0, -1, 1, -2, 2, -3, 3, -4 });
        s2[i*4+1] = @shuffle(u16, v0, v1, [8]i32{ 4, -5, 5, -6, 6, -7, 7, -8 });
        
        const v2: @Vector(8, u16) = @bitCast(s1[i*4+1]);
        const v3: @Vector(8, u16) = @bitCast(s1[i*4+3]);
        s2[i*4+2] = @shuffle(u16, v2, v3, [8]i32{ 0, -1, 1, -2, 2, -3, 3, -4 });
        s2[i*4+3] = @shuffle(u16, v2, v3, [8]i32{ 4, -5, 5, -6, 6, -7, 7, -8 });
    }

    var s3: [16]@Vector(4, u32) = undefined;
    inline for (0..2) |i| {
        inline for (0..4) |j| {
            const v0: @Vector(4, u32) = @bitCast(s2[i*8 + j]);
            const v1: @Vector(4, u32) = @bitCast(s2[i*8 + j + 4]);
            s3[i*8 + j] = @shuffle(u32, v0, v1, [4]i32{ 0, -1, 1, -2 });
            s3[i*8 + j + 4] = @shuffle(u32, v0, v1, [4]i32{ 2, -3, 3, -4 });
        }
    }

    var res: [16]@Vector(16, u8) = undefined;
    inline for (0..8) |i| {
        const v0: @Vector(2, u64) = @bitCast(s3[i]);
        const v1: @Vector(2, u64) = @bitCast(s3[i + 8]);
        res[i] = @bitCast(@shuffle(u64, v0, v1, [2]i32{ 0, -1 }));
        res[i + 8] = @bitCast(@shuffle(u64, v0, v1, [2]i32{ 1, -2 }));
    }

    return res;
}

pub fn transpose8x8(rows: [8]@Vector(8, u8)) [8]@Vector(8, u8) {
    const s1_0 = @shuffle(u8, rows[0], rows[1], [8]i32{ 0, -1, 1, -2, 2, -3, 3, -4 });
    const s1_1 = @shuffle(u8, rows[0], rows[1], [8]i32{ 4, -5, 5, -6, 6, -7, 7, -8 });
    const s1_2 = @shuffle(u8, rows[2], rows[3], [8]i32{ 0, -1, 1, -2, 2, -3, 3, -4 });
    const s1_3 = @shuffle(u8, rows[2], rows[3], [8]i32{ 4, -5, 5, -6, 6, -7, 7, -8 });
    const s1_4 = @shuffle(u8, rows[4], rows[5], [8]i32{ 0, -1, 1, -2, 2, -3, 3, -4 });
    const s1_5 = @shuffle(u8, rows[4], rows[5], [8]i32{ 4, -5, 5, -6, 6, -7, 7, -8 });
    const s1_6 = @shuffle(u8, rows[6], rows[7], [8]i32{ 0, -1, 1, -2, 2, -3, 3, -4 });
    const s1_7 = @shuffle(u8, rows[6], rows[7], [8]i32{ 4, -5, 5, -6, 6, -7, 7, -8 });

    const v1_0: @Vector(4, u16) = @bitCast(s1_0);
    const v1_1: @Vector(4, u16) = @bitCast(s1_2);
    const s2_0: [2]@Vector(4, u16) = .{
        @shuffle(u16, v1_0, v1_1, [4]i32{ 0, -1, 1, -2 }),
        @shuffle(u16, v1_0, v1_1, [4]i32{ 2, -3, 3, -4 }),
    };
    
    const v1_2: @Vector(4, u16) = @bitCast(s1_4);
    const v1_3: @Vector(4, u16) = @bitCast(s1_6);
    const s2_1: [2]@Vector(4, u16) = .{
        @shuffle(u16, v1_2, v1_3, [4]i32{ 0, -1, 1, -2 }),
        @shuffle(u16, v1_2, v1_3, [4]i32{ 2, -3, 3, -4 }),
    };

    const v1_4: @Vector(4, u16) = @bitCast(s1_1);
    const v1_5: @Vector(4, u16) = @bitCast(s1_3);
    const s2_2: [2]@Vector(4, u16) = .{
        @shuffle(u16, v1_4, v1_5, [4]i32{ 0, -1, 1, -2 }),
        @shuffle(u16, v1_4, v1_5, [4]i32{ 2, -3, 3, -4 }),
    };

    const v1_6: @Vector(4, u16) = @bitCast(s1_5);
    const v1_7: @Vector(4, u16) = @bitCast(s1_7);
    const s2_3: [2]@Vector(4, u16) = .{
        @shuffle(u16, v1_6, v1_7, [4]i32{ 0, -1, 1, -2 }),
        @shuffle(u16, v1_6, v1_7, [4]i32{ 2, -3, 3, -4 }),
    };

    const v2_0: @Vector(2, u32) = @bitCast(s2_0[0]);
    const v2_1: @Vector(2, u32) = @bitCast(s2_1[0]);
    const res0: @Vector(2, u32) = @shuffle(u32, v2_0, v2_1, [2]i32{ 0, -1 });
    const res4: @Vector(2, u32) = @shuffle(u32, v2_0, v2_1, [2]i32{ 1, -2 });

    const v2_2: @Vector(2, u32) = @bitCast(s2_0[1]);
    const v2_3: @Vector(2, u32) = @bitCast(s2_1[1]);
    const res2: @Vector(2, u32) = @shuffle(u32, v2_2, v2_3, [2]i32{ 0, -1 });
    const res6: @Vector(2, u32) = @shuffle(u32, v2_2, v2_3, [2]i32{ 1, -2 });

    const v2_4: @Vector(2, u32) = @bitCast(s2_2[0]);
    const v2_5: @Vector(2, u32) = @bitCast(s2_3[0]);
    const res1: @Vector(2, u32) = @shuffle(u32, v2_4, v2_5, [2]i32{ 0, -1 });
    const res5: @Vector(2, u32) = @shuffle(u32, v2_4, v2_5, [2]i32{ 1, -2 });

    const v2_6: @Vector(2, u32) = @bitCast(s2_2[1]);
    const v2_7: @Vector(2, u32) = @bitCast(s2_3[1]);
    const res3: @Vector(2, u32) = @shuffle(u32, v2_6, v2_7, [2]i32{ 0, -1 });
    const res7: @Vector(2, u32) = @shuffle(u32, v2_6, v2_7, [2]i32{ 1, -2 });

    return .{
        @bitCast(res0), @bitCast(res4), @bitCast(res2), @bitCast(res6),
        @bitCast(res1), @bitCast(res5), @bitCast(res3), @bitCast(res7),
    };
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
