const std = @import("std");
const DeflateWrapper = @import("deflate_wrapper").DeflateWrapper;

test "DeflateWrapper: decompress simple block" {
    // Compressed "Hello QwD!" using standard deflate
    const compressed = [_]u8{ 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x57, 0x08, 0x2c, 0x4f, 0x51, 0x04, 0x00 };
    var decompressed: [32]u8 = undefined;
    
    const len = try DeflateWrapper.decompressBgzfBlock(&compressed, &decompressed);
    
    try std.testing.expectEqualStrings("Hello Qwd!", decompressed[0..len]);
}
