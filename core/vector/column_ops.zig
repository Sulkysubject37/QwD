const std = @import("std");

pub fn countGcColumn(column: []const u8, count: usize) usize {
    var gc: usize = 0;
    const vec_size = 32;
    var i: usize = 0;
    
    while (i + vec_size <= count) : (i += vec_size) {
        const v: @Vector(vec_size, u8) = column[i..][0..vec_size].*;
        const is_g = v == @as(@Vector(vec_size, u8), @splat('G')) or v == @as(@Vector(vec_size, u8), @splat('g'));
        const is_c = v == @as(@Vector(vec_size, u8), @splat('C')) or v == @as(@Vector(vec_size, u8), @splat('c'));
        const is_gc = is_g or is_c;
        gc += @reduce(.Add, @as(@Vector(vec_size, u8), @select(u8, is_gc, @as(@Vector(vec_size, u8), @splat(1)), @as(@Vector(vec_size, u8), @splat(0)))));
    }
    
    // Residual
    while (i < count) : (i += 1) {
        const b = column[i];
        if (b == 'G' or b == 'C' or b == 'g' or b == 'c') gc += 1;
    }
    
    return gc;
}

pub fn sumQualityColumn(column: []const u8, count: usize) u64 {
    var sum: u64 = 0;
    const vec_size = 32;
    var i: usize = 0;
    
    while (i + vec_size <= count) : (i += vec_size) {
        const v: @Vector(vec_size, u8) = column[i..][0..vec_size].*;
        // phred = q - 33
        const mask = v >= @as(@Vector(vec_size, u8), @splat(33));
        const phreds = @select(u8, mask, v - @as(@Vector(vec_size, u8), @splat(33)), @as(@Vector(vec_size, u8), @splat(0)));
        sum += @reduce(.Add, @as(@Vector(vec_size, u16), phreds));
    }
    
    while (i < count) : (i += 1) {
        const q = column[i];
        sum += if (q >= 33) q - 33 else 0;
    }
    
    return sum;
}
