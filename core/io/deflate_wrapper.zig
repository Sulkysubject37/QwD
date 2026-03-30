const std = @import("std");

pub const c = @cImport({
    @cInclude("libdeflate.h");
});

pub const Decompressor = struct {
    handle: *c.libdeflate_decompressor,

    pub fn init() !Decompressor {
        const handle = c.libdeflate_alloc_decompressor() orelse return error.OutOfMemory;
        return Decompressor{ .handle = handle };
    }

    pub fn deinit(self: *Decompressor) void {
        c.libdeflate_free_decompressor(self.handle);
    }

    pub fn decompress(self: *Decompressor, in: []const u8, out: []u8) !usize {
        var actual_out_size: usize = 0;
        const result = c.libdeflate_gzip_decompress(
            self.handle,
            in.ptr,
            in.len,
            out.ptr,
            out.len,
            &actual_out_size,
        );

        return switch (result) {
            c.LIBDEFLATE_SUCCESS => actual_out_size,
            c.LIBDEFLATE_BAD_DATA => error.BadData,
            c.LIBDEFLATE_SHORT_OUTPUT => error.ShortOutput,
            c.LIBDEFLATE_INSUFFICIENT_SPACE => error.InsufficientSpace,
            else => error.UnknownError,
        };
    }
    
    /// For raw DEFLATE (e.g. inside GZIP blocks)
    pub fn decompress_raw(self: *Decompressor, in: []const u8, out: []u8) !usize {
        var actual_out_size: usize = 0;
        const result = c.libdeflate_deflate_decompress(
            self.handle,
            in.ptr,
            in.len,
            out.ptr,
            out.len,
            &actual_out_size,
        );

        return switch (result) {
            c.LIBDEFLATE_SUCCESS => actual_out_size,
            c.LIBDEFLATE_BAD_DATA => error.BadData,
            c.LIBDEFLATE_SHORT_OUTPUT => error.ShortOutput,
            c.LIBDEFLATE_INSUFFICIENT_SPACE => error.InsufficientSpace,
            else => error.UnknownError,
        };
    }
};
