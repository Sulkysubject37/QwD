const std = @import("std");

/// BUFFERED IO KERNEL
pub const BufferedReader = struct {
    file: std.Io.File,
    io: std.Io,
    buffer: [256 * 1024]u8 = undefined,
    pos: usize = 0,
    len: usize = 0,

    pub fn init(file: std.Io.File, io: std.Io) BufferedReader {
        return .{
            .file = file,
            .io = io,
        };
    }

    pub fn read(self: *BufferedReader, dest: []u8) !usize {
        if (self.pos >= self.len) {
            // Use stable POSIX read to bypass std.Io refactor instability
            const n = try std.posix.read(self.file.handle, self.buffer[0..]);
            self.len = n;
            self.pos = 0;
            if (self.len == 0) return 0;
        }

        const size = @min(dest.len, self.len - self.pos);
        @memcpy(dest[0..size], self.buffer[self.pos .. self.pos + size]);
        self.pos += size;
        return size;
    }

    pub fn readAtLeast(self: *BufferedReader, dest: []u8, n: usize) !usize {
        var total: usize = 0;
        while (total < n) {
            const amt = try self.read(dest[total..]);
            if (amt == 0) break;
            total += amt;
        }
        return total;
    }
};
