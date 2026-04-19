const std = @import("std");
const DeflateEngine = @import("custom_deflate.zig").DeflateEngine;

/// GzipProtocol: A pure-Zig wrapper for GZIP and BGZF formats.
pub const GzipProtocol = struct {
    engine: DeflateEngine,
    
    pub fn init(reader: std.Io.Reader) GzipProtocol {
        return .{
            .engine = DeflateEngine.init(reader),
        };
    }

    /// Decompresses a single GZIP member (block).
    pub fn decompressMember(self: *GzipProtocol, sink: anytype) !void {
        // 1. Parse Header
        var header: [10]u8 = undefined;
        try self.engine.sieve.inner_reader.readNoEof(&header);
        if (header[0] != 0x1F or header[1] != 0x8B) return error.NotGzip;
        
        const flags = header[3];
        if (flags & 0x04 != 0) { // FEXTRA
            var xlen_buf: [2]u8 = undefined;
            try self.engine.sieve.inner_reader.readNoEof(&xlen_buf);
            const xlen = std.mem.readInt(u16, &xlen_buf, .little);
            try self.engine.sieve.inner_reader.skipBytes(xlen, .{});
        }
        if (flags & 0x08 != 0) try self.skipZeroTerminated(); // FNAME
        if (flags & 0x10 != 0) try self.skipZeroTerminated(); // FCOMMENT
        if (flags & 0x02 != 0) try self.engine.sieve.inner_reader.skipBytes(2, .{}); // FHCRC

        // 2. Decompress DEFLATE data
        try self.engine.decompress(sink);

        // 3. Parse Trailer (CRC32 and ISIZE)
        var trailer: [8]u8 = undefined;
        try self.engine.sieve.inner_reader.readNoEof(&trailer);
        // (Validation omitted for Phase P.2 prototype)
    }

    fn skipZeroTerminated(self: *GzipProtocol) !void {
        var buf: [1]u8 = undefined;
        while (true) {
            try self.engine.sieve.inner_reader.readNoEof(&buf);
            if (buf[0] == 0) break;
        }
    }
};
