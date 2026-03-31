const std = @import("std");
const BgzfNativeReader = @import("bgzf_native_reader").BgzfNativeReader;

pub const BgzfChunkBuilder = struct {
    reader: *BgzfNativeReader,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, reader: *BgzfNativeReader) BgzfChunkBuilder {
        return .{
            .reader = reader,
            .allocator = allocator,
        };
    }

    pub fn nextChunk(self: *BgzfChunkBuilder) !?[]u8 {
        const block = (try self.reader.nextBlock()) orelse return null;
        // nextBlock() returns a newly allocated buffer.
        // We cast to []u8 because ParallelScheduler expects []u8 for is_alloc cleanup.
        return @constCast(block.compressed_data);
    }
};
