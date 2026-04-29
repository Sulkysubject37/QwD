const deflate_impl = @import("deflate_impl");

pub const DeflateWrapper = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !DeflateWrapper {
        return DeflateWrapper{ .allocator = allocator };
    }

    pub fn deinit(self: *DeflateWrapper) void {
        _ = self;
    }

    pub fn decompressBgzfBlock(self: *const DeflateWrapper, compressed: []const u8, decompressed: []u8) !usize {
        _ = self;
        return deflate_impl.decompress(compressed, decompressed);
    }
};
