const std = @import("std");
const deflate_impl = @import("deflate_impl");

pub fn main() !void {
    std.debug.print("[Test] Starting Deflate test...\n", .{});

    // "Hello World" compressed with raw DEFLATE (fixed Huffman)
    // Generated via: echo -n "Hello World" | zlib-flate -compress | tail -c +3 | head -c -4 | xxd -i
    const compressed = [_]u8{ 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x57, 0x08, 0xcf, 0x2f, 0xca, 0x49, 0x01, 0x00 };
    var decompressed: [1024]u8 = undefined;

    const n = try deflate_impl.decompress(&compressed, &decompressed);
    
    std.debug.print("[Test] Decompressed {d} bytes: {s}\n", .{ n, decompressed[0..n] });
    
    if (std.mem.eql(u8, decompressed[0..n], "Hello World")) {
        std.debug.print("[Test] SUCCESS\n", .{});
    } else {
        std.debug.print("[Test] FAILURE: Expected 'Hello World'\n", .{});
    }
}
