const std = @import("std");

pub const BlockReader = struct {
    reader: ?std.io.AnyReader = null,
    buffer: []u8,
    pos: usize,
    end: usize,
    mmap_handle: ?[]u8 = null,
    is_mmap: bool = false,

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, buffer_size: usize) !BlockReader {
        return BlockReader{
            .reader = reader,
            .buffer = try allocator.alloc(u8, buffer_size),
            .pos = 0,
            .end = 0,
        };
    }

    pub fn initMmap(file: std.fs.File) !BlockReader {
        const size = try file.getEndPos();
        if (size == 0) return error.EmptyFile;
        
        const ptr = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ,
            .{ .TYPE = .PRIVATE },
            file.handle,
            0,
        );
        return BlockReader{
            .buffer = ptr,
            .pos = 0,
            .end = size,
            .mmap_handle = ptr,
            .is_mmap = true,
        };
    }

    pub fn deinit(self: *BlockReader, allocator: std.mem.Allocator) void {
        if (self.is_mmap) {
            const ptr = self.mmap_handle.?;
            const aligned_ptr = @as([]align(std.mem.page_size) const u8, @alignCast(ptr));
            std.posix.munmap(aligned_ptr);
        } else {
            allocator.free(self.buffer);
        }
    }

    pub fn fill(self: *BlockReader) !usize {
        if (self.is_mmap) return 0; // Everything is already in memory

        const remaining = self.end - self.pos;
        if (remaining > 0 and self.pos > 0) {
            std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[self.pos..self.end]);
        }
        self.pos = 0;
        self.end = remaining;
        
        const read_len = try self.reader.?.read(self.buffer[self.end..]);
        self.end += read_len;
        return read_len;
    }
};
