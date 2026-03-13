const std = @import("std");

pub const BlockReader = struct {
    reader: std.io.AnyReader,
    buffer: []u8,
    pos: usize,
    end: usize,

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, buffer_size: usize) !BlockReader {
        return BlockReader{
            .reader = reader,
            .buffer = try allocator.alloc(u8, buffer_size),
            .pos = 0,
            .end = 0,
        };
    }

    pub fn deinit(self: *BlockReader, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
    }

    pub fn fill(self: *BlockReader) !usize {
        const remaining = self.end - self.pos;
        if (remaining > 0 and self.pos > 0) {
            std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[self.pos..self.end]);
        }
        self.pos = 0;
        self.end = remaining;
        
        const read_len = try self.reader.read(self.buffer[self.end..]);
        self.end += read_len;
        return read_len;
    }
};
