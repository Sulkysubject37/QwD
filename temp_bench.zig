const std = @import("std");
const builtin = @import("builtin");

// --- BIT SIEVE ---
pub const BitSieve = struct {
    bit_buffer: u64 = 0, bit_count: u8 = 0, inner_reader: std.io.AnyReader,
    pub fn init(reader: std.io.AnyReader) BitSieve { return .{ .inner_reader = reader }; }
    pub fn refill(self: *BitSieve) !void {
        while (self.bit_count <= 56) {
            var byte: u8 = undefined;
            const n = self.inner_reader.read(std.mem.asBytes(&byte)) catch 0;
            if (n == 0) break;
            self.bit_buffer |= (@as(u64, byte) << @as(u6, @intCast(self.bit_count)));
            self.bit_count += 8;
        }
    }
    pub inline fn peekBits(self: *const BitSieve, comptime n: u6) u64 { return self.bit_buffer & ((@as(u64, 1) << n) - 1); }
    pub inline fn consume(self: *BitSieve, n: u6) void { self.bit_buffer >>= n; self.bit_count -= n; }
    pub inline fn readBits(self: *BitSieve, comptime n: u6) !u64 {
        if (self.bit_count < n) try self.refill();
        const val = self.peekBits(n); self.consume(n); return val;
    }
    pub fn readBitsRuntime(self: *BitSieve, n: u6) !u64 {
        if (n == 0) return 0;
        if (self.bit_count < n) try self.refill();
        const val = self.bit_buffer & ((@as(u64, 1) << n) - 1);
        self.consume(n); return val;
    }
    pub fn alignToByte(self: *BitSieve) void { const skip: u6 = @intCast(self.bit_count % 8); if (skip > 0) self.consume(skip); }
};

// --- HUFFMAN ---
pub const HuffmanDecoder = struct {
    lookup: [4096]u32 = undefined,
    pub fn init() HuffmanDecoder { var self = HuffmanDecoder{}; @memset(&self.lookup, 0); return self; }
    pub fn build(self: *HuffmanDecoder, lengths: []const u8) !void {
        var count = [_]u16{0} ** 16;
        for (lengths) |len| if (len > 0) { count[len] += 1; };
        var next_code = [_]u16{0} ** 16;
        var code: u16 = 0;
        for (1..16) |bits| { code = (code + count[bits - 1]) << 1; next_code[bits] = code; }
        @memset(&self.lookup, 0);
        for (lengths, 0..) |len, symbol| {
            if (len == 0) continue;
            const c = next_code[len]; next_code[len] += 1;
            if (len <= 12) {
                const rev = reverseBits(c, @intCast(len));
                const entry = (@as(u32, len) << 16) | @as(u32, @intCast(symbol));
                const fill_bits = 12 - len;
                for (0..(@as(usize, 1) << @intCast(fill_bits))) |i| {
                    const idx = rev | (i << @intCast(len));
                    self.lookup[idx] = entry;
                }
            }
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
    var res: u16 = 0; var c = code; var i: u4 = 0;
    while (i < len) : (i += 1) { res = (res << 1) | (c & 1); c >>= 1; }
    return res;
}

// --- LZ77 ---
pub const Lz77Engine = struct {
    window: [32768]u8 = undefined, pos: usize = 0,
    pub fn init() Lz77Engine { var self = Lz77Engine{}; @memset(&self.window, 0); return self; }
    pub inline fn appendByte(self: *Lz77Engine, byte: u8) void {
        self.window[self.pos] = byte; self.pos = (self.pos + 1) & 0x7FFF;
    }
    pub fn copyMatch(self: *Lz77Engine, distance: u15, length: u16, sink: anytype) !void {
        var len = length;
        var src_pos = (@as(usize, 32768) + self.pos - @as(usize, distance)) & 0x7FFF;
        while (len > 0) {
            const byte = self.window[src_pos];
            try sink.emit(byte);
            self.window[self.pos] = byte;
            self.pos = (self.pos + 1) & 0x7FFF;
            src_pos = (src_pos + 1) & 0x7FFF;
            len -= 1;
        }
    }
};

// --- DEFLATE ---
pub const DeflateEngine = struct {
    sieve: BitSieve, lz77: Lz77Engine, lit_decoder: HuffmanDecoder, dist_decoder: HuffmanDecoder,
    total_emitted: usize = 0,
    pub fn init(reader: std.io.AnyReader) DeflateEngine {
        return .{ .sieve = BitSieve.init(reader), .lz77 = Lz77Engine.init(), .lit_decoder = HuffmanDecoder.init(), .dist_decoder = HuffmanDecoder.init() };
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
        var i: usize = 0; while (i < len) : (i += 1) {
            const byte = @as(u8, @intCast(try self.sieve.readBitsRuntime(8)));
            try sink.emit(byte); self.lz77.appendByte(byte); self.total_emitted += 1;
        }
    }
    fn decompressFixed(self: *DeflateEngine, sink: anytype) !void {
        var lit_lengths: [288]u8 = undefined; var i: usize = 0;
        while (i <= 143) : (i += 1) lit_lengths[i] = 8;
        while (i <= 255) : (i += 1) lit_lengths[i] = 9;
        while (i <= 279) : (i += 1) lit_lengths[i] = 7;
        while (i <= 287) : (i += 1) lit_lengths[i] = 8;
        try self.lit_decoder.build(&lit_lengths);
        var dist_lengths = [_]u8{5} ** 32; try self.dist_decoder.build(&dist_lengths);
        try self.decodeHufData(sink);
    }
    fn decompressDynamic(self: *DeflateEngine, sink: anytype) !void {
        const hlit = (try self.sieve.readBits(5)) + 257;
        const hdist = (try self.sieve.readBits(5)) + 1;
        const hclen = (try self.sieve.readBits(4)) + 4;
        var cl_lengths = [_]u8{0} ** 19;
        const cl_order = [_]u8{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };
        for (0..hclen) |i| cl_lengths[cl_order[i]] = @intCast(try self.sieve.readBits(3));
        var cl_decoder = HuffmanDecoder.init(); try cl_decoder.build(&cl_lengths);
        var all_lengths: [288 + 32]u8 = undefined; var count: usize = 0; const total_expected = hlit + hdist;
        while (count < total_expected) {
            const symbol = try cl_decoder.decode(&self.sieve);
            if (symbol < 16) { all_lengths[count] = @intCast(symbol); count += 1; }
            else if (symbol == 16) {
                const repeat = (try self.sieve.readBitsRuntime(2)) + 3; const last = all_lengths[count - 1];
                for (0..@intCast(repeat)) |_| { all_lengths[count] = last; count += 1; }
            } else if (symbol == 17) {
                const repeat = (try self.sieve.readBitsRuntime(3)) + 3;
                for (0..@intCast(repeat)) |_| { all_lengths[count] = 0; count += 1; }
            } else if (symbol == 18) {
                const repeat = (try self.sieve.readBitsRuntime(7)) + 11;
                for (0..@intCast(repeat)) |_| { all_lengths[count] = 0; count += 1; }
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
                const byte = @as(u8, @intCast(symbol)); try sink.emit(byte); self.lz77.appendByte(byte); self.total_emitted += 1;
            } else if (symbol == 256) break else {
                const len = try self.decodeLength(symbol); const dist_sym = try self.dist_decoder.decode(&self.sieve);
                const dist = try self.decodeDistance(dist_sym); try self.lz77.copyMatch(@intCast(dist), @intCast(len), sink);
                self.total_emitted += len;
            }
        }
    }
    fn decodeLength(self: *DeflateEngine, symbol: u16) !u16 {
        const base_lengths = [_]u16{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 91, 115, 131, 163, 195, 227, 258 };
        const extra_bits = [_]u5{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
        const extra = try self.sieve.readBitsRuntime(extra_bits[symbol - 257]);
        return base_lengths[symbol - 257] + @as(u16, @intCast(extra));
    }
    fn decodeDistance(self: *DeflateEngine, symbol: u16) !u16 {
        const base_dist = [_]u16{ 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
        const extra_bits = [_]u5{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
        const extra = try self.sieve.readBitsRuntime(extra_bits[symbol]);
        return base_dist[symbol] + @as(u16, @intCast(extra));
    }
};

// --- BENCHMARK ---
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    const file_path = if (args.len > 1) args[1] else return error.NoFile;
    const file = try std.fs.cwd().openFile(file_path, .{});
    const data = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
    const thread_counts = [_]u8{ 1, 2, 4, 8 };
    std.debug.print("--- Parallel Native Decompression Scaling ---\n", .{});
    for (thread_counts) |tc| {
        var threads = try allocator.alloc(std.Thread, tc);
        var engines = try allocator.alloc(DeflateEngine, tc);
        const start = std.time.nanoTimestamp();
        // Each thread processes a separate slice of the data to avoid header hunting
        const chunk_size = data.len / tc;
        for (0..tc) |i| {
            const slice = data[i*chunk_size..if(i==tc-1) data.len else (i+1)*chunk_size];
            threads[i] = try std.Thread.spawn(.{}, worker, .{slice, &engines[i]});
        }
        for (threads) |t| t.join();
        const end = std.time.nanoTimestamp();
        const elapsed = @as(f64, @floatFromInt(end - start)) / 1e9;
        var total_bytes: usize = 0; for(engines) |e| total_bytes += e.total_emitted;
        const throughput = @as(f64, @floatFromInt(total_bytes)) / (1024 * 1024 * elapsed);
        std.debug.print("Threads: {d:<2} | Time: {d:6.3}s | Total Bytes: {d:>10} | Throughput: {d:8.2} MB/s\n", .{tc, elapsed, total_bytes, throughput});
        allocator.free(threads); allocator.free(engines);
    }
}
const NullSink = struct { pub fn emit(self: @This(), byte: u8) !void { _ = self; _ = byte; } };
fn worker(data: []const u8, engine_ptr: *DeflateEngine) void {
    var fbs = std.io.fixedBufferStream(data);
    while (fbs.pos + 10 < data.len) {
        if (data[fbs.pos] == 0x1f and data[fbs.pos+1] == 0x8b) {
            const flags = data[fbs.pos + 3];
            fbs.pos += 10;
            if (flags & 0x04 != 0) {
                const xlen = std.mem.readInt(u16, data[fbs.pos..][0..2], .little);
                fbs.pos += 2 + xlen;
            }
            var engine = DeflateEngine.init(fbs.reader().any());
            var sink = NullSink{};
            engine.decompress(&sink) catch {};
            engine_ptr.total_emitted += engine.total_emitted;
        } else fbs.pos += 1;
    }
}
