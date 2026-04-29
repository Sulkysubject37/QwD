const std = @import("std");

/// High-Performance Decompression via libdeflate (Industry Standard)
pub const LibDeflate = struct {
    pub const Decompressor = opaque {};
    
    extern "c" fn libdeflate_alloc_decompressor() ?*Decompressor;
    extern "c" fn libdeflate_free_decompressor(d: *Decompressor) void;
    extern "c" fn libdeflate_deflate_decompress(
        d: *Decompressor,
        in: [*]const u8,
        in_n: usize,
        out: [*]u8,
        out_n_max: usize,
        actual_out_n: ?*usize,
    ) c_int;
};

pub fn decompress(compressed: []const u8, decompressed: []u8) !usize {
    // 1. Thread-local decompressor cache or one-shot? 
    // For now, one-shot for correctness, then we can optimize.
    const d = LibDeflate.libdeflate_alloc_decompressor() orelse return error.OutOfMemory;
    defer LibDeflate.libdeflate_free_decompressor(d);
    
    var actual: usize = 0;
    const result = LibDeflate.libdeflate_deflate_decompress(
        d,
        compressed.ptr,
        compressed.len,
        decompressed.ptr,
        decompressed.len,
        &actual,
    );
    
    if (result != 0) return error.DecompressionFailed;
    return actual;
}
