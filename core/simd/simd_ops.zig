const std = @import("std");

pub var force_scalar: bool = false;

pub fn simd_enabled() bool {
    if (force_scalar) return false;
    // Zig @Vector provides hardware acceleration where available
    return true;
}

/// Accelerated GC counting using SIMD
pub fn countGcSimd(seq: []const u8) usize {
    if (!simd_enabled()) return countGcScalar(seq);
    
    const vec_size = 32;
    var count: usize = 0;
    var i: usize = 0;

    const g_vec: @Vector(vec_size, u8) = @splat('G');
    const c_vec: @Vector(vec_size, u8) = @splat('C');
    const gl_vec: @Vector(vec_size, u8) = @splat('g');
    const cl_vec: @Vector(vec_size, u8) = @splat('c');

    while (i + vec_size <= seq.len) : (i += vec_size) {
        const v: @Vector(vec_size, u8) = seq[i..][0..vec_size].*;
        const is_G = v == g_vec;
        const is_C = v == c_vec;
        const is_gl = v == gl_vec;
        const is_cl = v == cl_vec;
        
        const ones: @Vector(vec_size, u16) = @splat(1);
        const zeros: @Vector(vec_size, u16) = @splat(0);
        
        count += @reduce(.Add, @select(u16, is_G, ones, zeros));
        count += @reduce(.Add, @select(u16, is_C, ones, zeros));
        count += @reduce(.Add, @select(u16, is_gl, ones, zeros));
        count += @reduce(.Add, @select(u16, is_cl, ones, zeros));
    }

    while (i < seq.len) : (i += 1) {
        const b = seq[i];
        if (b == 'G' or b == 'C' or b == 'g' or b == 'c') count += 1;
    }
    return count;
}

pub fn countGcScalar(seq: []const u8) usize {
    var count: usize = 0;
    for (seq) |b| {
        if (b == 'G' or b == 'C' or b == 'g' or b == 'c') count += 1;
    }
    return count;
}

pub fn sumPhredSimd(qual: []const u8) u64 {
    if (!simd_enabled()) return sumPhredScalar(qual);
    
    const vec_size = 32;
    var sum: u64 = 0;
    var i: usize = 0;
    const sub_vec: @Vector(vec_size, u8) = @splat(33);

    while (i + vec_size <= qual.len) : (i += vec_size) {
        const v: @Vector(vec_size, u8) = qual[i..][0..vec_size].*;
        
        // Clamp to 33 to prevent underflow
        const clamped = @select(u8, v < sub_vec, sub_vec, v);
        const phreds = clamped - sub_vec;
        
        sum += @reduce(.Add, @as(@Vector(vec_size, u64), phreds));
    }

    while (i < qual.len) : (i += 1) {
        const q = qual[i];
        const phred = if (q >= 33) q - 33 else 0;
        sum += phred;
    }
    return sum;
}

pub fn sumPhredScalar(qual: []const u8) u64 {
    var sum: u64 = 0;
    for (qual) |q| {
        const phred = if (q >= 33) q - 33 else 0;
        sum += phred;
    }
    return sum;
}
