const std = @import("std");
const bgzf_native_reader = @import("bgzf_native_reader");
const Reader = @import("reader_interface").Reader;

pub const BlockReader = struct {
    bgzf: bgzf_native_reader.BgzfNativeReader,
    reader: Reader,
    buffer: []u8,
    pos: usize = 0,
    len: usize = 0,

    pub fn init(allocator: std.mem.Allocator, reader: Reader, buf_size: usize) !BlockReader {
        return BlockReader{
            .bgzf = try bgzf_native_reader.BgzfNativeReader.init(allocator),
            .reader = reader,
            .buffer = try allocator.alloc(u8, buf_size),
        };
    }

    pub fn deinit(self: *BlockReader, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
        self.bgzf.deinit();
    }

    pub fn readLine(self: *BlockReader) !?[]const u8 {
        while (true) {
            if (self.pos >= self.len) {
                const read = try self.reader.read(self.buffer);
                if (read == 0) return null;
                self.len = read;
                self.pos = 0;
            }

            const current_data = self.buffer[self.pos..self.len];
            if (std.mem.indexOfScalar(u8, current_data, '\n')) |nl_pos| {
                const start = self.pos;
                var end = self.pos + nl_pos;
                self.pos = end + 1;

                if (end > start and self.buffer[end - 1] == '\r') {
                    end -= 1;
                }
                return self.buffer[start..end];
            } else {
                // This is a partial line at the end of the buffer. 
                // We must shift it to the start and read more.
                const remaining = self.len - self.pos;
                std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[self.pos..self.len]);
                const read = try self.reader.read(self.buffer[remaining..]);
                if (read == 0) {
                    // Last partial line without newline
                    const line = self.buffer[0..remaining];
                    self.pos = remaining;
                    self.len = remaining;
                    return if (line.len > 0) line else null;
                }
                self.len = remaining + read;
                self.pos = 0;
            }
        }
    }
};
