const std = @import("std");
const mode = @import("mode");
const bgzf_mod = @import("bgzf_native_reader");
const deflate_impl = @import("deflate_impl");

pub const BlockReader = struct {
    file: std.Io.File,
    io: std.Io,
    buffer: []u8,
    pos: usize,
    end: usize,
    allocator: std.mem.Allocator,
    is_gzip: bool = false,
    bgzf: ?bgzf_mod.BgzfNativeReader = null,
    eof: bool = false,
    first_block_checked: bool = false,

    pub fn initWithFile(allocator: std.mem.Allocator, file: std.Io.File, io: std.Io, buffer_size: usize) !BlockReader {
        const buf = try allocator.alloc(u8, buffer_size);
        return BlockReader{
            .file = file,
            .io = io,
            .buffer = buf,
            .pos = 0,
            .end = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BlockReader, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.allocator.free(self.buffer);
    }

    pub fn fill(self: *BlockReader) !usize {
        const remaining = self.end - self.pos;
        if (remaining > 0 and self.pos > 0) {
            std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[self.pos..self.end]);
        }
        self.pos = 0;
        self.end = remaining;
        
        if (!self.first_block_checked) {
            var magic: [2]u8 = undefined;
            const m_iov = [_][]u8{magic[0..]};
            const n = try self.file.readStreaming(self.io, &m_iov);
            if (n == 2 and magic[0] == 0x1F and magic[1] == 0x8B) {
                self.is_gzip = true;
                self.bgzf = try bgzf_mod.BgzfNativeReader.init(self.allocator, undefined);
                // Use system lseek directly in 0.16.0-dev
                _ = std.posix.system.lseek(self.file.handle, 0, 0); // 0 = SEEK_SET
            } else if (n > 0) {
                @memcpy(self.buffer[self.end..self.end+n], magic[0..n]);
                self.end += n;
            }
            self.first_block_checked = true;
        }

        if (self.is_gzip) {
            if (try self.bgzf.?.nextBlock(self.file, self.io)) |block| {
                defer self.allocator.free(block.compressed_data);
                const out_n = try deflate_impl.decompress(block.compressed_data, self.buffer[self.end..]);
                self.end += out_n;
                return out_n;
            } else {
                self.eof = true;
                return 0;
            }
        } else {
            const iov = [_][]u8{self.buffer[self.end..]};
            const n = self.file.readStreaming(self.io, &iov) catch |err| if (err == error.EndOfStream) 0 else return err;
            self.end += n;
            if (n == 0) self.eof = true;
            return n;
        }
    }

    pub fn readLine(self: *BlockReader) !?[]const u8 {
        while (true) {
            const window = self.buffer[self.pos..self.end];
            if (std.mem.indexOfScalar(u8, window, '\n')) |rel_idx| {
                const line = window[0..rel_idx];
                self.pos += rel_idx + 1;
                if (line.len > 0 and line[line.len - 1] == '\r') {
                    return line[0 .. line.len - 1];
                }
                return line;
            }
            if (self.eof and self.pos == self.end) return null;
            if (self.eof) {
                const line = self.buffer[self.pos..self.end];
                self.pos = self.end;
                return line;
            }
            const n_read = try self.fill();
            if (n_read == 0 and self.pos == self.end) return null;
        }
    }
};
