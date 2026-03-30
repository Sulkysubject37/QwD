const std = @import("std");
const builtin = @import("builtin");
const gzip_reader = @import("gzip_reader");

pub const BlockReader = struct {
    reader: ?std.io.AnyReader = null,
    file_fallback: ?std.fs.File = null,
    gzip: ?*gzip_reader.GzipReader = null, // Store as pointer for stability
    buffer: []u8,
    pos: usize,
    end: usize,
    mmap_handle: ?[]u8 = null,
    is_mmap: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, buffer_size: usize) !BlockReader {
        return BlockReader{
            .reader = reader,
            .buffer = try allocator.alloc(u8, buffer_size),
            .pos = 0,
            .end = 0,
            .allocator = allocator,
        };
    }

    pub fn initGzip(allocator: std.mem.Allocator, reader: std.io.AnyReader, buffer_size: usize, gzip_mode: @import("mode").GzipMode) !BlockReader {
        // Heap allocate GzipReader so background threads have a stable pointer
        const gz = try allocator.create(gzip_reader.GzipReader);
        gz.* = try gzip_reader.GzipReader.init(allocator, reader, gzip_mode);
        try gz.start();
        
        return BlockReader{
            .gzip = gz,
            .buffer = try allocator.alloc(u8, buffer_size),
            .pos = 0,
            .end = 0,
            .allocator = allocator,
        };
    }

    pub fn initMmap(allocator: std.mem.Allocator, file: std.fs.File) !BlockReader {
        if (builtin.os.tag == .windows) {
            return BlockReader{
                .file_fallback = file,
                .buffer = try allocator.alloc(u8, 1024 * 1024),
                .pos = 0,
                .end = 0,
                .allocator = allocator,
            };
        }

        const size_u64 = try file.getEndPos();
        if (size_u64 == 0) return error.EmptyFile;
        const size = std.math.cast(usize, size_u64) orelse return error.FileTooLarge;
        
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
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BlockReader, allocator: std.mem.Allocator) void {
        if (self.gzip) |gz| {
            gz.deinit(allocator);
            allocator.destroy(gz);
        }
        if (self.is_mmap) {
            if (builtin.os.tag != .windows) {
                const ptr = self.mmap_handle.?;
                const aligned_ptr = @as([]align(std.mem.page_size) const u8, @alignCast(ptr));
                std.posix.munmap(aligned_ptr);
            }
        } else {
            allocator.free(self.buffer);
        }
    }

    pub fn fill(self: *BlockReader) !usize {
        if (self.is_mmap) return 0;

        const remaining = self.end - self.pos;
        if (remaining > 0 and self.pos > 0) {
            std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[self.pos..self.end]);
        }
        self.pos = 0;
        self.end = remaining;
        
        var total_read: usize = 0;
        while (self.end < self.buffer.len) {
            const read_len = if (self.gzip) |gz|
                try gz.read(self.buffer[self.end..])
            else if (self.reader) |r| 
                try r.read(self.buffer[self.end..]) 
            else if (self.file_fallback) |f| 
                try f.read(self.buffer[self.end..])
            else return error.ReaderUnavailable;

            if (read_len == 0) break;
            self.end += read_len;
            total_read += read_len;
        }

        return total_read;
    }
};
