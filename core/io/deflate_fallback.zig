const std = @import("std");

pub fn decompress(compressed: []const u8, decompressed: []u8) !usize {
    var fbs = std.Io.FixedBufferStream.init(compressed);
    var decompressor = std.compress.flate.decompressor(fbs.reader());
    return decompressor.readSliceShort(decompressed);
}
