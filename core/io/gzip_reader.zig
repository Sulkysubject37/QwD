const std = @import("std");
const deflate_wrapper = @import("deflate_wrapper");
const ring_buffer = @import("ring_buffer");
const mode = @import("mode");

const Io = std.Io;

pub const GzipReader = struct {
    file: std.Io.File,
    io: Io,
    inflator: deflate_wrapper.DeflateWrapper,
    ring: *ring_buffer.RingBuffer(u8),
    allocator: std.mem.Allocator,
    eof: bool = false,
    compressed_buf: []u8,
    decompressed_buf: []u8,

    pub fn init(allocator: std.mem.Allocator, file: std.Io.File, io: Io) !*GzipReader {
        const self = try allocator.create(GzipReader);
        self.* = .{
            .file = file,
            .io = io,
            .inflator = try deflate_wrapper.DeflateWrapper.init(allocator),
            .ring = try ring_buffer.RingBuffer(u8).init(allocator, 1024 * 1024),
            .allocator = allocator,
            .compressed_buf = try allocator.alloc(u8, 64 * 1024),
            .decompressed_buf = try allocator.alloc(u8, 128 * 1024),
        };
        return self;
    }

    pub fn deinit(self: *GzipReader) void {
        self.inflator.deinit();
        self.ring.deinit();
        self.allocator.free(self.compressed_buf);
        self.allocator.free(self.decompressed_buf);
        self.allocator.destroy(self);
    }

    pub fn readSliceShort(self: *GzipReader, dest: []u8) !usize {
        if (self.ring.count() < dest.len and !self.eof) {
            try self.fillRing();
        }

        const to_read = @min(dest.len, self.ring.count());
        if (to_read == 0) return 0;

        return self.ring.read(dest[0..to_read]);
    }

    fn fillRing(self: *GzipReader) !void {
        const iov = [_][]u8{self.compressed_buf};
        const n = self.file.readStreaming(self.io, &iov) catch |err| if (err == error.EndOfStream) 0 else return err;
        
        if (n == 0) {
            self.eof = true;
            return;
        }

        const out_n = try self.inflator.decompressBgzfBlock(self.compressed_buf[0..n], self.decompressed_buf);
        
        _ = self.ring.write(self.decompressed_buf[0..out_n]);
    }
};
