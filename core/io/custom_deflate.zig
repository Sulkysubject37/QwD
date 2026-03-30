const std = @import("std");
const BitSieve = @import("bit_sieve.zig").BitSieve;
const HuffmanDecoder = @import("huffman_decoder.zig").HuffmanDecoder;
const Lz77Engine = @import("lz77_engine.zig").Lz77Engine;

pub const DeflateEngine = struct {
    sieve: BitSieve,
    lz77: Lz77Engine,
    lit_decoder: HuffmanDecoder,
    dist_decoder: HuffmanDecoder,
    
    pub fn init(reader: std.io.AnyReader) DeflateEngine {
        return .{
            .sieve = BitSieve.init(reader),
            .lz77 = Lz77Engine.init(),
            .lit_decoder = HuffmanDecoder.init(),
            .dist_decoder = HuffmanDecoder.init(),
        };
    }

    pub fn decompress(self: *DeflateEngine, sink: anytype) !void {
        var is_final: bool = false;
        while (!is_final) {
            try self.sieve.refill();
            is_final = (try self.sieve.readBits(1)) == 1;
            const block_type = try self.sieve.readBits(2);
            
            switch (block_type) {
                0 => try self.decompressUncompressed(sink),
                1 => try self.decompressFixed(sink),
                2 => try self.decompressDynamic(sink),
                else => return error.InvalidBlockType,
            }
        }
    }

    fn decompressUncompressed(self: *DeflateEngine, sink: anytype) !void {
        self.sieve.alignToByte();
        const len = @as(u16, @intCast(try self.sieve.readBits(16)));
        const nlen = @as(u16, @intCast(try self.sieve.readBits(16)));
        if (len != (~nlen & 0xFFFF)) return error.InvalidUncompressedBlock;
        
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const byte = @as(u8, @intCast(try self.sieve.readBitsRuntime(8)));
            try sink.emit(byte);
            self.lz77.appendByte(byte);
        }
    }

    fn decompressFixed(self: *DeflateEngine, sink: anytype) !void {
        var lit_lengths: [288]u8 = undefined;
        var i: usize = 0;
        while (i <= 143) : (i += 1) lit_lengths[i] = 8;
        while (i <= 255) : (i += 1) lit_lengths[i] = 9;
        while (i <= 279) : (i += 1) lit_lengths[i] = 7;
        while (i <= 287) : (i += 1) lit_lengths[i] = 8;
        try self.lit_decoder.build(&lit_lengths);

        var dist_lengths = [_]u8{5} ** 32;
        try self.dist_decoder.build(&dist_lengths);

        try self.decodeHufData(sink);
    }

    fn decompressDynamic(self: *DeflateEngine, sink: anytype) !void {
        const hlit = (try self.sieve.readBits(5)) + 257;
        const hdist = (try self.sieve.readBits(5)) + 1;
        const hclen = (try self.sieve.readBits(4)) + 4;
        
        var cl_lengths = [_]u8{0} ** 19;
        const cl_order = [_]u8{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };
        for (0..hclen) |i| {
            cl_lengths[cl_order[i]] = @intCast(try self.sieve.readBits(3));
        }
        
        var cl_decoder = HuffmanDecoder.init();
        try cl_decoder.build(&cl_lengths);
        
        var all_lengths: [288 + 32]u8 = undefined;
        var count: usize = 0;
        const total_expected = hlit + hdist;
        
        while (count < total_expected) {
            const symbol = try cl_decoder.decode(&self.sieve);
            if (symbol < 16) {
                all_lengths[count] = @intCast(symbol);
                count += 1;
            } else if (symbol == 16) {
                const repeat = (try self.sieve.readBitsRuntime(2)) + 3;
                const last = all_lengths[count - 1];
                for (0..@intCast(repeat)) |_| {
                    all_lengths[count] = last;
                    count += 1;
                }
            } else if (symbol == 17) {
                const repeat = (try self.sieve.readBitsRuntime(3)) + 3;
                for (0..@intCast(repeat)) |_| {
                    all_lengths[count] = 0;
                    count += 1;
                }
            } else if (symbol == 18) {
                const repeat = (try self.sieve.readBitsRuntime(7)) + 11;
                for (0..@intCast(repeat)) |_| {
                    all_lengths[count] = 0;
                    count += 1;
                }
            }
        }
        
        try self.lit_decoder.build(all_lengths[0..hlit]);
        try self.dist_decoder.build(all_lengths[hlit..total_expected]);
        
        try self.decodeHufData(sink);
    }

    fn decodeHufData(self: *DeflateEngine, sink: anytype) !void {
        while (true) {
            if (self.sieve.bit_count < 32) try self.sieve.refill();
            const symbol = try self.lit_decoder.decode(&self.sieve);
            if (symbol < 256) {
                const byte = @as(u8, @intCast(symbol));
                try sink.emit(byte);
                self.lz77.appendByte(byte);
            } else if (symbol == 256) {
                break; // End of block
            } else {
                const len = try self.decodeLength(symbol);
                const dist_sym = try self.dist_decoder.decode(&self.sieve);
                const dist = try self.decodeDistance(dist_sym);
                try self.lz77.copyMatch(@intCast(dist), @intCast(len), sink);
            }
        }
    }

    fn decodeLength(self: *DeflateEngine, symbol: u16) !u16 {
        const base_lengths = [_]u16{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 91, 115, 131, 163, 195, 227, 258 };
        const extra_bits = [_]u5{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
        const idx = symbol - 257;
        const extra = try self.sieve.readBitsRuntime(extra_bits[idx]);
        return base_lengths[idx] + @as(u16, @intCast(extra));
    }

    fn decodeDistance(self: *DeflateEngine, symbol: u16) !u16 {
        const base_dist = [_]u16{ 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
        const extra_bits = [_]u5{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
        const extra = try self.sieve.readBitsRuntime(extra_bits[symbol]);
        return base_dist[symbol] + @as(u16, @intCast(extra));
    }
};

const BufferSink = struct {
    buf: std.ArrayList(u8),
    pub fn emit(self: *BufferSink, byte: u8) !void {
        try self.buf.append(byte);
    }
};

test "DeflateEngine: uncompressed block" {
    const allocator = std.testing.allocator;
    const data = [_]u8{ 0b00000001, 0x05, 0x00, 0xfa, 0xff, 'H', 'e', 'l', 'l', 'o' };
    var fbs = std.io.fixedBufferStream(&data);
    var engine = DeflateEngine.init(fbs.reader().any());
    var sink = BufferSink{ .buf = std.ArrayList(u8).init(allocator) };
    defer sink.buf.deinit();
    try engine.decompress(&sink);
    try std.testing.expectEqualStrings("Hello", sink.buf.items);
}

test "DeflateEngine: fixed block" {
    const allocator = std.testing.allocator;
    const data = [_]u8{ 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00 };
    var fbs = std.io.fixedBufferStream(&data);
    var engine = DeflateEngine.init(fbs.reader().any());
    var sink = BufferSink{ .buf = std.ArrayList(u8).init(allocator) };
    defer sink.buf.deinit();
    try engine.decompress(&sink);
    try std.testing.expectEqualStrings("Hello", sink.buf.items);
}

test "DeflateEngine: dynamic block (Hello QwD!)" {
    const allocator = std.testing.allocator;
    // 1f8b08000000000002fff348cdc9c957082c775104006a6651710a000000
    const data = [_]u8{ 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x57, 0x08, 0x2c, 0x77, 0x51, 0x04, 0x00 };
    var fbs = std.io.fixedBufferStream(&data);
    var engine = DeflateEngine.init(fbs.reader().any());
    var sink = BufferSink{ .buf = std.ArrayList(u8).init(allocator) };
    defer sink.buf.deinit();
    try engine.decompress(&sink);
    try std.testing.expectEqualStrings("Hello QwD!", sink.buf.items);
}
