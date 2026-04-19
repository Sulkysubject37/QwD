const std = @import("std");

pub fn decompress(compressed: []const u8, decompressed: []u8) !usize {
    const c = @cImport({
        @cInclude("libdeflate.h");
    });
    
    const decompressor = c.libdeflate_alloc_decompressor() orelse return error.LibdeflateAllocFailed;
    defer c.libdeflate_free_decompressor(decompressor);
    
    var actual_out_n: usize = 0;
    const result = c.libdeflate_deflate_decompress(
        decompressor,
        compressed.ptr,
        compressed.len,
        decompressed.ptr,
        decompressed.len,
        &actual_out_n,
    );
    
    if (result != 0) return error.LibdeflateDecompressionFailed;
    return actual_out_n;
}
