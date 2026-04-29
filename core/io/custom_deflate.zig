const std = @import("std");
const BitSieve = @import("bit_sieve.zig").BitSieve;
const HuffmanDecoder = @import("huffman_decoder.zig").HuffmanDecoder;
const Lz77Engine = @import("lz77_engine.zig").Lz77Engine;

pub const DeflateEngine = struct {
    sieve: BitSieve,
    lz77: Lz77Engine,
    lit_decoder: HuffmanDecoder,
    dist_decoder: HuffmanDecoder,
    
    pub fn init(reader: *std.Io.Reader) DeflateEngine {
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
            if (self.sieve.bit_count < 3) try self.sieve.refill();
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
        if (self.sieve.bit_count < 32) try self.sieve.refill();
        const len = @as(u16, @intCast(try self.sieve.readBits(16)));
        const nlen = @as(u16, @intCast(try self.sieve.readBits(16)));
        if (len != (~nlen & 0xFFFF)) return error.InvalidUncompressedBlock;
        
        var i: usize = 0;
        while (i < len) : (i += 1) {
            if (self.sieve.bit_count < 8) try self.sieve.refill();
            const byte = @as(u8, @intCast(try self.sieve.readBits(8)));
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
        if (self.sieve.bit_count < 14) try self.sieve.refill();
        const hlit = (try self.sieve.readBits(5)) + 257;
        const hdist = (try self.sieve.readBits(5)) + 1;
        const hclen = (try self.sieve.readBits(4)) + 4;
        
        var cl_lengths = [_]u8{0} ** 19;
        const cl_order = [_]u8{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };
        for (0..hclen) |i| {
            if (self.sieve.bit_count < 3) try self.sieve.refill();
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
                if (self.sieve.bit_count < 2) try self.sieve.refill();
                const repeat = (try self.sieve.readBits(2)) + 3;
                const last = all_lengths[count - 1];
                for (0..@intCast(repeat)) |_| {
                    all_lengths[count] = last;
                    count += 1;
                }
            } else if (symbol == 17) {
                if (self.sieve.bit_count < 3) try self.sieve.refill();
                const repeat = (try self.sieve.readBits(3)) + 3;
                for (0..@intCast(repeat)) |_| {
                    all_lengths[count] = 0;
                    count += 1;
                }
            } else if (symbol == 18) {
                if (self.sieve.bit_count < 7) try self.sieve.refill();
                const repeat = (try self.sieve.readBits(7)) + 11;
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
                try self.lz77.copyMatch(dist, len, sink);
            }
        }
    }

    fn decodeLength(self: *DeflateEngine, symbol: u16) !u16 {
        const base_lengths = [_]u16{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 91, 115, 131, 163, 195, 227, 258 };
        const extra_bits = [_]u5{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
        const idx = symbol - 257;
        const bits = extra_bits[idx];
        if (bits > 0) {
            if (self.sieve.bit_count < bits) try self.sieve.refill();
            return base_lengths[idx] + @as(u16, @intCast(try self.sieve.readBitsRuntime(bits)));
        }
        return base_lengths[idx];
    }

    fn decodeDistance(self: *DeflateEngine, symbol: u16) !u16 {
        const base_dist = [_]u16{ 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
        const extra_bits = [_]u5{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
        const bits = extra_bits[symbol];
        if (bits > 0) {
            if (self.sieve.bit_count < bits) try self.sieve.refill();
            return base_dist[symbol] + @as(u16, @intCast(try self.sieve.readBitsRuntime(bits)));
        }
        return base_dist[symbol];
    }
};
