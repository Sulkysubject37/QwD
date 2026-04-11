const std = @import("std");

/// BGZF (Blocked GNU Zip Format) Native Reader
/// Strictly follows Phase P.2 Agent A requirements.
pub const BgzfNativeReader = struct {
    inner_reader: std.io.AnyReader,
    allocator: std.mem.Allocator,
    buffer: []u8,
    eof: bool = false,

    pub const Block = struct {
        compressed_data: []const u8,
        uncompressed_len: u32,
        total_member_len: usize,
    };

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader) !BgzfNativeReader {
        return BgzfNativeReader{
            .inner_reader = reader,
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, 128 * 1024), // Large enough for any BGZF member
        };
    }

    pub fn deinit(self: *BgzfNativeReader) void {
        self.allocator.free(self.buffer);
    }

    /// Iterates block-by-block. Returns next compressed block or null.
    pub fn isBgzf(reader: anytype) bool {
        // We need to look for GZIP magic + FLG.FEXTRA + 'BC' extra field
        // Since we can't easily 'peek' AnyReader without a buffer, 
        // we'll assume the caller passes a peekable stream or we just try to read the first header.
        var header: [20]u8 = undefined;
        const n = reader.readAll(&header) catch return false;
        if (n < 20) return false;
        
        // Magic
        if (header[0] != 0x1F or header[1] != 0x8B or header[2] != 0x08) return false;
        // FEXTRA bit
        if (header[3] & 0x04 == 0) return false;
        
        // Look for 'BC'
        var i: usize = 12; // Start of extra fields
        const xlen = std.mem.readInt(u16, header[10..12], .little);
        const limit = @min(10 + 2 + xlen, 20);
        while (i + 4 <= limit) {
            if (header[i] == 'B' and header[i+1] == 'C') return true;
            const slen = std.mem.readInt(u16, header[i+2..i+4][0..2], .little);
            i += 4 + slen;
        }
        return false;
    }

    pub fn nextBlock(self: *BgzfNativeReader) !?Block {
        if (self.eof) return null;

        // Read GZIP Header (10 bytes)
        var header: [10]u8 = undefined;
        const h_len = self.inner_reader.readAll(&header) catch |err| {
            if (err == error.EndOfStream) { self.eof = true; return null; }
            return err;
        };
        if (h_len == 0) { self.eof = true; return null; }
        if (h_len < 10) return error.TruncatedHeader;

        // Validate GZIP Magic and CM=8 (Deflate)
        if (header[0] != 0x1F or header[1] != 0x8B) return error.InvalidGzipMagic;
        if (header[2] != 0x08) return error.UnsupportedCompressionMethod;

        var total_member_len: usize = 0;
        var payload_len: usize = 0;
        var isize_val: u32 = 0;

        if (header[3] & 0x04 != 0) {
            // BGZF Path: Parse Extra Fields to find 'BC'
            var xlen_buf: [2]u8 = undefined;
            try self.inner_reader.readNoEof(&xlen_buf);
            const xlen = std.mem.readInt(u16, &xlen_buf, .little);

            var extra = try self.allocator.alloc(u8, xlen);
            defer self.allocator.free(extra);
            try self.inner_reader.readNoEof(extra);

            var bsize: ?u16 = null;
            var i: usize = 0;
            while (i + 4 <= xlen) {
                const si1 = extra[i];
                const si2 = extra[i + 1];
                const slen = std.mem.readInt(u16, extra[i + 2 .. i + 4][0..2], .little);
                if (si1 == 'B' and si2 == 'C' and slen == 2) {
                    bsize = std.mem.readInt(u16, extra[i + 4 .. i + 6][0..2], .little);
                    break;
                }
                i += 4 + slen;
            }

            const block_size = bsize orelse return error.NotBGZF;
            total_member_len = @as(usize, block_size) + 1;
            payload_len = total_member_len - 10 - 2 - xlen - 8;
            
            const compressed_data = try self.allocator.alloc(u8, payload_len);
            errdefer self.allocator.free(compressed_data);
            try self.inner_reader.readNoEof(compressed_data);

            var trailer: [8]u8 = undefined;
            try self.inner_reader.readNoEof(&trailer);
            isize_val = std.mem.readInt(u32, trailer[4..8][0..4], .little);

            // Skip EOF blocks
            if (isize_val == 0 and payload_len == 2) {
                self.allocator.free(compressed_data);
                return self.nextBlock();
            }

            // Phase Sec-Zero: Hardened Decompression Ceiling
            // Prevent BGZF Decompression Bombs
            const MAX_EXPANSION_RATIO = 32;
            if (payload_len > 0 and isize_val > payload_len * MAX_EXPANSION_RATIO) {
                self.allocator.free(compressed_data);
                return error.DecompressionBomb;
            }

            return Block{
                .compressed_data = compressed_data,
                .uncompressed_len = isize_val,
                .total_member_len = total_member_len,
            };
        } else {
            // Standard GZ Path: Not supported by nextBlock() iterator for parallel chunking.
            // ParallelScheduler must fallback to the prefetch stream for non-BGZF GZ.
            return error.NotBGZF;
        }
    }
};
