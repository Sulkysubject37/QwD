const std = @import("std");

/// BGZF (Blocked GNU Zip Format) Native Reader
pub const BgzfNativeReader = struct {
    allocator: std.mem.Allocator,

    pub const Block = struct {
        compressed_data: []u8,
        uncompressed_len: u32,
        total_member_len: usize,
    };

    pub fn init(allocator: std.mem.Allocator, _: anytype) !BgzfNativeReader {
        return BgzfNativeReader{ .allocator = allocator };
    }

    pub fn deinit(_: *BgzfNativeReader) void {}

    pub fn nextBlockHardened(self: *BgzfNativeReader, file: std.Io.File, io: anytype, magic: ?*const [2]u8) !?Block {
        var header: [12]u8 = undefined;
        if (magic) |m| {
            header[0] = m[0];
            header[1] = m[1];
            const n = try file.readStreaming(io, &[_][]u8{header[2..12]});
            if (n < 10) return null;
        } else {
            const n = file.readStreaming(io, &[_][]u8{header[0..12]}) catch |err| if (err == error.EndOfStream) return null else return err;
            if (n == 0) return null;
            if (n < 12) return error.TruncatedBgzfHeader;
        }

        if (header[0] != 0x1F or header[1] != 0x8B) return null;
        const flg = header[3];
        if (flg & 0x04 == 0) return error.NotBGZF; // No extra field

        const xlen = std.mem.readInt(u16, header[10..12], .little);
        const extra = try self.allocator.alloc(u8, xlen);
        defer self.allocator.free(extra);
        const n_extra = try file.readStreaming(io, &[_][]u8{extra});
        if (n_extra < xlen) return error.TruncatedBgzfExtra;

        var bsize: ?u16 = null;
        var off: usize = 0;
        while (off + 4 <= xlen) {
            const si1 = extra[off];
            const si2 = extra[off + 1];
            const slen = std.mem.readInt(u16, extra[off + 2 .. off + 4][0..2], .little);
            if (si1 == 'B' and si2 == 'C' and slen == 2) {
                bsize = std.mem.readInt(u16, extra[off + 4 .. off + 6][0..2], .little);
                break;
            }
            off += 4 + slen;
        }

        const block_size = bsize orelse return error.InvalidBgzfExtra;
        const total_member_len = @as(usize, block_size) + 1;
        const compressed_len = block_size - @as(u32, @intCast(xlen)) - 19;

        const compressed_data = try self.allocator.alloc(u8, compressed_len);
        errdefer self.allocator.free(compressed_data);

        const n_comp = try file.readStreaming(io, &[_][]u8{compressed_data});
        if (n_comp < compressed_len) return error.TruncatedBgzfData;

        var footer: [8]u8 = undefined;
        const n_foot = try file.readStreaming(io, &[_][]u8{&footer});
        if (n_foot < 8) return error.TruncatedBgzfFooter;

        const isize_val = std.mem.readInt(u32, footer[4..8], .little);

        // SEC-ZERO FIREWALL: Prevent Gzip/BGZF Bombs
        if (@as(u64, isize_val) > (@as(u64, compressed_len) * 32)) {
            return error.DecompressionBomb;
        }

        return Block{
            .compressed_data = compressed_data,
            .uncompressed_len = isize_val,
            .total_member_len = total_member_len,
        };
    }

    pub fn nextBlock(self: *BgzfNativeReader, file: std.Io.File, io: anytype) !?Block {
        return self.nextBlockHardened(file, io, null);
    }
};
