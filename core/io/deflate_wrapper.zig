const std = @import("std");
const build_options = @import("build_options");
const DeflateEngine = @import("custom_deflate").DeflateEngine;

pub const DeflateWrapper = struct {
    pub fn decompressBgzfBlock(compressed: []const u8, decompressed: []u8) !usize {
        if (build_options.HAVE_LIBDEFLATE) {
            return decompressLibdeflate(compressed, decompressed);
        }

        // Fallback to std.compress.flate (faster than custom)
        var fbs = std.io.fixedBufferStream(compressed);
        var decompressor = std.compress.flate.decompressor(fbs.reader());
        
        return decompressor.read(decompressed);
    }

    fn decompressLibdeflate(compressed: []const u8, decompressed: []u8) !usize {
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

    const BufferSink = struct {
        buf: []u8,
        pos: usize,

        pub fn emit(self: *BufferSink, byte: u8) !void {
            if (self.pos >= self.buf.len) return error.BufferOverflow;
            self.buf[self.pos] = byte;
            self.pos += 1;
        }
    };
};
