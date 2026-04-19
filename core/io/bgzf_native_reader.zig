const std = @import("std");

/// BGZF (Blocked GNU Zip Format) Native Reader
pub const BgzfNativeReader = struct {
    allocator: std.mem.Allocator,

    pub const Block = struct {
        compressed_data: []u8,
        uncompressed_len: u32,
        total_member_len: usize,
    };

    pub fn init(allocator: std.mem.Allocator, _: *anyopaque) !BgzfNativeReader {
        return BgzfNativeReader{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *BgzfNativeReader) void {}

    pub fn nextBlock(self: *BgzfNativeReader, file: std.Io.File, io: std.Io) !?Block {
        var header: [18]u8 = undefined;
        const h_iov = [_][]u8{header[0..]};
        const h_n = file.readStreaming(io, &h_iov) catch |err| if (err == error.EndOfStream) return null else return err;
        if (h_n == 0) return null;
        if (h_n < 18) return error.TruncatedGzip;

        if (header[0] != 0x1f or header[1] != 0x8b) return error.InvalidGzipMagic;

        const bsize = std.mem.readInt(u16, header[16..18], .little);
        const total_member_len = @as(usize, bsize) + 1;
        const compressed_payload_len = total_member_len - 18 - 8;

        const compressed_data = try self.allocator.alloc(u8, compressed_payload_len);
        errdefer self.allocator.free(compressed_data);

        const d_iov = [_][]u8{compressed_data};
        const d_n = try file.readStreaming(io, &d_iov);
        if (d_n < compressed_payload_len) return error.TruncatedGzip;

        var footer: [8]u8 = undefined;
        const f_iov = [_][]u8{footer[0..]};
        const f_n = try file.readStreaming(io, &f_iov);
        if (f_n < 8) return error.TruncatedGzip;

        const isize_val = std.mem.readInt(u32, footer[4..8], .little);

        return Block{
            .compressed_data = compressed_data,
            .uncompressed_len = isize_val,
            .total_member_len = total_member_len,
        };
    }
};
