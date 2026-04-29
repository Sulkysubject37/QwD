const std = @import("std");
const block_reader = @import("block_reader");
const Reader = @import("reader_interface").Reader;

pub const Read = struct {
    id: []const u8,
    seq: []const u8,
    qual: []const u8,
};

pub const FastqParser = struct {
    reader: block_reader.BlockReader,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, reader: Reader, buf_size: usize) !FastqParser {
        return FastqParser{
            .reader = try block_reader.BlockReader.init(allocator, reader, buf_size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FastqParser) void {
        self.reader.deinit(self.allocator);
    }

    pub fn next(self: *FastqParser) !?Read {
        while (true) {
            const line1 = (try self.reader.readLine()) orelse return null;
            if (line1.len == 0 or line1[0] != '@') continue;
            
            const id = line1[1..];
            const seq = (try self.reader.readLine()) orelse return null;
            _ = (try self.reader.readLine()) orelse return null; // +
            const qual = (try self.reader.readLine()) orelse return null;
            
            return Read{
                .id = id,
                .seq = seq,
                .qual = qual,
            };
        }
    }
};
