const std = @import("std");
const deflate_mod = @import("deflate");

// Mock module for the test to avoid path issues
const BitSieve = @import("bit_sieve");
const HuffmanDecoder = @import("huffman");
const Lz77Engine = @import("lz77");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    if (args.len < 2) return error.MissingFilePath;
    const file_path = args[1];
    
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    
    const data = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
    defer allocator.free(data);

    const thread_counts = [_]u8{ 1, 2, 4, 8 };
    
    std.debug.print("--- Parallel Decompression Test (Native) ---\n", .{});
    for (thread_counts) |tc| {
        var threads = try allocator.alloc(std.Thread, tc);
        
        const start = std.time.nanoTimestamp();
        
        for (0..tc) |i| {
            threads[i] = try std.Thread.spawn(.{}, worker, .{data});
        }
        
        for (threads) |t| t.join();
        
        const end = std.time.nanoTimestamp();
        const elapsed = @as(f64, @floatFromInt(end - start)) / 1e9;
        const throughput = (@as(f64, @floatFromInt(tc)) * @as(f64, @floatFromInt(data.len))) / (1024 * 1024 * elapsed);
        
        std.debug.print("Threads: {d:<2} | Time: {d:6.3}s | Throughput: {d:8.2} MB/s\n", .{tc, elapsed, throughput});
        allocator.free(threads);
    }
}

const NullSink = struct {
    pub fn emit(self: @This(), byte: u8) !void {
        _ = self; _ = byte;
    }
};

fn worker(data: []const u8) void {
    // We use @import here to satisfy the run command
    const DeflateEngine = @import("../core/io/custom_deflate.zig").DeflateEngine;
    var fbs = std.io.fixedBufferStream(data);
    var engine = DeflateEngine.init(fbs.reader().any());
    var sink = NullSink{};
    if (data.len > 10 and data[0] == 0x1f and data[1] == 0x8b) {
        fbs.pos = 10;
    }
    engine.decompress(&sink) catch {};
}
