const std = @import("std");

/// BGZF (Blocked GNU Zip Format) Native Reader
pub const BgzfNativeReader = struct {
    allocator: std.mem.Allocator,
    decompressed_buf: []u8,
    decompressed_pos: usize = 0,
    decompressed_len: usize = 0,

    pub const Block = struct {
        compressed_data: []u8,
        uncompressed_len: u32,
        total_member_len: usize,
    };

    pub fn init(allocator: std.mem.Allocator) !BgzfNativeReader {
        return BgzfNativeReader{ 
            .allocator = allocator,
            .decompressed_buf = try allocator.alloc(u8, 64 * 1024),
        };
    }

    pub fn deinit(self: *BgzfNativeReader) void {
        self.allocator.free(self.decompressed_buf);
    }

    pub fn nextBlockHardened(self: *BgzfNativeReader, reader: anytype, magic: ?*?[2]u8) !?Block {
        var header: [18]u8 = undefined;
        
        if (magic != null and magic.?.* != null) {
            const m = magic.?.*.?;
            header[0] = m[0];
            header[1] = m[1];
            const n = try reader.readAtLeast(header[2..12], 10);
            if (n < 10) return null;
            magic.?.* = null; // CONSUMED
        } else {
            // We use readSliceAll to ensure we get exactly 12 bytes or EOF
            const n = reader.read(header[0..12]) catch |err| {
                if (err == error.EndOfStream) return null;
                std.debug.print("[BGZF] Read error: {any}\n", .{err});
                return err;
            };
            if (n == 0) return null;
            if (n < 12) return error.TruncatedBgzfHeader;
        }

        if (header[0] != 0x1F or header[1] != 0x8B) {
            std.debug.print("[BGZF] Invalid Magic: {x} {x}\n", .{header[0], header[1]});
            return null;
        }
        
        const flg = header[3];
        if (flg & 0x04 == 0) return error.NotBGZF;

        const xlen = std.mem.readInt(u16, header[10..12], .little);
        
        var bsize: ?u16 = null;
        if (xlen == 6) {
            const n_extra = try reader.read(header[12..18]);
            if (n_extra < 6) return error.TruncatedBgzfExtra;
            if (header[12] == 'B' and header[13] == 'C' and header[14] == 2 and header[15] == 0) {
                bsize = std.mem.readInt(u16, header[16..18], .little);
            } else {
                return error.InvalidBgzfExtra;
            }
        } else {
            const extra = try self.allocator.alloc(u8, xlen);
            defer self.allocator.free(extra);
            const n_extra = try reader.read(extra);
            if (n_extra < xlen) return error.TruncatedBgzfExtra;

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
        }

        const block_size = bsize orelse return error.InvalidBgzfExtra;
        const total_member_len = @as(usize, block_size) + 1;
        const compressed_len = total_member_len - 12 - @as(usize, xlen) - 8;

        const compressed_data = try self.allocator.alloc(u8, compressed_len);
        errdefer self.allocator.free(compressed_data);

        const n_comp = try reader.read(compressed_data);
        if (n_comp < compressed_len) return error.TruncatedBgzfData;

        var footer: [8]u8 = undefined;
        const n_foot = try reader.read(&footer);
        if (n_foot < 8) return error.TruncatedBgzfFooter;

        const isize_val = std.mem.readInt(u32, footer[4..8], .little);

        return Block{
            .compressed_data = compressed_data,
            .uncompressed_len = isize_val,
            .total_member_len = total_member_len,
        };
    }

    pub fn nextBlock(self: *BgzfNativeReader, reader: anytype) !?Block {
        var magic: ?[2]u8 = null;
        return self.nextBlockHardened(reader, &magic);
    }
};
