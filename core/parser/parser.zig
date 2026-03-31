const std = @import("std");
const block_reader = @import("block_reader");
const mode_mod = @import("mode");

pub const Read = struct {
    id: []const u8,
    seq: []const u8,
    qual: []const u8,
    arena: ?*std.heap.ArenaAllocator = null,
};

pub const FastqParser = struct {
    reader: *block_reader.BlockReader,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, buf_size: usize) !FastqParser {
        const br = try allocator.create(block_reader.BlockReader);
        br.* = try block_reader.BlockReader.init(allocator, reader, buf_size);
        return FastqParser{
            .reader = br,
            .allocator = allocator,
        };
    }

    pub fn initGzip(allocator: std.mem.Allocator, reader: std.io.AnyReader, buf_size: usize, gzip_mode: mode_mod.GzipMode) !FastqParser {
        const br = try allocator.create(block_reader.BlockReader);
        br.* = try block_reader.BlockReader.initGzip(allocator, reader, buf_size, gzip_mode);
        return FastqParser{
            .reader = br,
            .allocator = allocator,
        };
    }

    pub fn initMmap(allocator: std.mem.Allocator, file: std.fs.File) !FastqParser {
        const br = try allocator.create(block_reader.BlockReader);
        br.* = try block_reader.BlockReader.initMmap(allocator, file);
        return FastqParser{
            .reader = br,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FastqParser) void {
        self.reader.deinit(self.allocator);
        self.allocator.destroy(self.reader);
    }

    pub fn next(self: *FastqParser, buf: []u8) !?Read {
        while (true) {
            const line1 = (try self.reader.readLine()) orelse return null;
            if (line1.len == 0 or line1[0] != '@') continue;
            
            const id_raw = line1[1..];
            const seq_raw = (try self.reader.readLine()) orelse return null;
            _ = (try self.reader.readLine()) orelse return null; // skip +
            const qual_raw = (try self.reader.readLine()) orelse return null;
            
            if (seq_raw.len != qual_raw.len) return error.MismatchedSequenceQuality;

            if (buf.len < id_raw.len + seq_raw.len + qual_raw.len) {
                // Return slices directly if buffer is too small, though this is less stable
                return Read{
                    .id = id_raw,
                    .seq = seq_raw,
                    .qual = qual_raw,
                    .arena = null,
                };
            }

            // Stable Copy into buf
            @memcpy(buf[0..id_raw.len], id_raw);
            @memcpy(buf[id_raw.len .. id_raw.len + seq_raw.len], seq_raw);
            @memcpy(buf[id_raw.len + seq_raw.len .. id_raw.len + seq_raw.len + qual_raw.len], qual_raw);

            const id = buf[0..id_raw.len];
            const seq = buf[id_raw.len .. id_raw.len + seq_raw.len];
            const qual = buf[id_raw.len + seq_raw.len .. id_raw.len + seq_raw.len + qual_raw.len];

            return Read{
                .id = id,
                .seq = seq,
                .qual = qual,
                .arena = null,
            };
        }
    }
};
