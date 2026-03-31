const std = @import("std");
const block_reader = @import("block_reader");
const parser_mod = @import("parser");

pub const ChunkBuilder = struct {
    parser: *parser_mod.FastqParser,
    chunk_size: usize,

    pub fn init(parser: *parser_mod.FastqParser, chunk_size: usize) ChunkBuilder {
        return .{
            .parser = parser,
            .chunk_size = chunk_size,
        };
    }

    pub fn nextChunk(self: *ChunkBuilder) !?[]u8 {
        if (!self.parser.reader.is_mmap) {
            if (self.parser.reader.end - self.parser.reader.pos < self.chunk_size) {
                const read_len = try self.parser.reader.fill();
                if (read_len == 0 and self.parser.reader.pos >= self.parser.reader.end) return null;
            }
        } else {
            if (self.parser.reader.pos >= self.parser.reader.end) return null;
        }

        const start_pos = self.parser.reader.pos;
        var end_pos = start_pos;
        var bytes_accumulated: usize = 0;

        while (bytes_accumulated < self.chunk_size) {
            var parse_buf: [4096]u8 = undefined;
            if (try self.parser.next(&parse_buf)) |_| {
                end_pos = self.parser.reader.pos;
                bytes_accumulated = end_pos - start_pos;
            } else {
                break;
            }
        }

        if (end_pos > start_pos) {
            const chunk = self.parser.reader.buffer[start_pos..end_pos];
            // Do not advance pos, parser.next() already advanced it!
            return chunk;
        } else {
            return null;
        }
    }
};
