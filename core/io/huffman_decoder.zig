const std = @import("std");
const BitSieve = @import("bit_sieve.zig").BitSieve;

pub const HuffmanDecoder = struct {
    // 12-bit lookup table. Format: (len << 16) | symbol
    lookup: [4096]u32 = undefined,

    pub fn init() HuffmanDecoder {
        var self = HuffmanDecoder{};
        @memset(&self.lookup, 0);
        return self;
    }

    pub fn build(self: *HuffmanDecoder, lengths: []const u8) !void {
        var count = [_]u16{0} ** 16;
        for (lengths) |len| if (len > 0) { count[len] += 1; };

        var next_code = [_]u16{0} ** 16;
        var code: u16 = 0;
        for (1..16) |bits| {
            code = (code + count[bits - 1]) << 1;
            next_code[bits] = code;
        }

        @memset(&self.lookup, 0);
        for (lengths, 0..) |len, symbol| {
            if (len == 0) continue;
            const c = next_code[len];
            next_code[len] += 1;

            if (len <= 12) {
                // Correct DEFLATE bit-order: symbols are reversed bitwise
                const rev = reverseBits(c, @intCast(len));
                const entry = (@as(u32, len) << 16) | @as(u32, @intCast(symbol));
                const fill_bits = 12 - len;
                for (0..(@as(usize, 1) << @intCast(fill_bits))) |i| {
                    const idx = rev | (i << @intCast(len));
                    self.lookup[idx] = entry;
                }
            } else return error.UnsupportedHuffmanLength;
        }
    }

    pub inline fn decode(self: *const HuffmanDecoder, sieve: *BitSieve) !u16 {
        const peeked = sieve.peekBits(12);
        const entry = self.lookup[peeked];
        if (entry == 0) return error.InvalidHuffmanSymbol;
        sieve.consume(@intCast(entry >> 16));
        return @intCast(entry & 0xFFFF);
    }
};

fn reverseBits(code: u16, len: u4) u16 {
    var res: u16 = 0;
    var c = code;
    var i: u4 = 0;
    while (i < len) : (i += 1) {
        res = (res << 1) | (c & 1);
        c >>= 1;
    }
    return res;
}
