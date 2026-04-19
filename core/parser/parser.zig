const std = @import("std");
const block_reader = @import("block_reader");
const mode_mod = @import("mode");
const parser_errors = @import("parser_errors");

pub const Read = struct {
    id: []const u8,
    seq: []const u8,
    qual: []const u8,
    arena: ?*std.heap.ArenaAllocator = null,
};

pub const FastqParser = struct {
    reader: block_reader.BlockReader,
    allocator: std.mem.Allocator,

    pub fn initWithFile(allocator: std.mem.Allocator, file: std.Io.File, io: std.Io, buf_size: usize) !FastqParser {
        return FastqParser{
            .reader = try block_reader.BlockReader.initWithFile(allocator, file, io, buf_size),
            .allocator = allocator,
        };
    }

    pub fn initWithBuffer(allocator: std.mem.Allocator, reader: std.Io.Reader) !FastqParser {
        return FastqParser{
            .reader = try block_reader.BlockReader.initFromReader(allocator, reader),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FastqParser) void {
        self.reader.deinit(self.allocator);
    }

    pub fn next(self: *FastqParser, buf: []u8) !?Read {
        while (true) {
            const line1 = (try self.reader.readLine()) orelse return null;
            if (line1.len == 0 or line1[0] != '@') continue;
            
            const id_raw = line1[1..];
            const seq_raw = (try self.reader.readLine()) orelse return null;
            _ = (try self.reader.readLine()) orelse return null; // skip +
            const qual_raw = (try self.reader.readLine()) orelse return null;
            
            if (seq_raw.len != qual_raw.len) {
                // If we are in APPROX or some specialized mode, we might ignore this,
                // but for stability we return null to signal end of valid records.
                return null;
            }

            if (buf.len < id_raw.len + seq_raw.len + qual_raw.len) {
                return Read{
                    .id = id_raw,
                    .seq = seq_raw,
                    .qual = qual_raw,
                    .arena = null,
                };
            }

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
