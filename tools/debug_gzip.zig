const std = @import("std");

// Import core files directly using absolute/relative paths to bypass CLI module issues
const mode_mod = @import("../core/config/mode.zig");
const GzipReader = @import("../core/io/gzip_reader.zig").GzipReader;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: debug_gzip <compressed_file> <original_file>\n", .{});
        return;
    }

    const comp_path = args[1];
    const orig_path = args[2];

    const c_file = try std.fs.cwd().openFile(comp_path, .{});
    defer c_file.close();

    const o_file = try std.fs.cwd().openFile(orig_path, .{});
    defer o_file.close();

    // Standard allocation to avoid any dangling pointer issues
    var gz = try allocator.create(GzipReader);
    gz.* = try GzipReader.init(allocator, c_file.reader().any(), .AUTO);
    gz.proxy_ptr.parent = gz; // CRITICAL FIX
    try gz.start();
    defer {
        gz.deinit(allocator);
        allocator.destroy(gz);
    }

    var gz_reader = gz.anyReader();
    var o_reader = o_file.reader();

    var buf_gz: [65536]u8 = undefined;
    var buf_orig: [65536]u8 = undefined;
    var offset: usize = 0;

    std.debug.print("Comparing: {s} vs {s}\n", .{comp_path, orig_path});

    while (true) {
        const n_orig = try o_reader.read(&buf_orig);
        if (n_orig == 0) break;

        var n_gz_total: usize = 0;
        while (n_gz_total < n_orig) {
            const n_gz = try gz_reader.read(buf_gz[n_gz_total..n_orig]);
            if (n_gz == 0) {
                std.debug.print("FAILURE: Premature EOF from GzipReader at offset {}\n", .{ offset + n_gz_total });
                return error.PrematureEOF;
            }
            n_gz_total += n_gz;
        }

        if (!std.mem.eql(u8, buf_gz[0..n_orig], buf_orig[0..n_orig])) {
            for (0..n_orig) |i| {
                if (buf_gz[i] != buf_orig[i]) {
                    std.debug.print("FAILURE: Data mismatch at offset {}: GZ=0x{X}, ORIG=0x{X}\n", .{ offset + i, buf_gz[i], buf_orig[i] });
                    return error.Mismatch;
                }
            }
        }

        offset += n_orig;
        if (offset % (10 * 1024 * 1024) == 0) {
            std.debug.print("Verified {} MB...\n", .{offset / (1024 * 1024)});
        }
    }

    // Verify trailing data in GZ
    const trailing = try gz_reader.read(&buf_gz);
    if (trailing > 0) {
        std.debug.print("FAILURE: GzipReader has trailing data ({} bytes) beyond original file size.\n", .{trailing});
        return error.TrailingData;
    }

    std.debug.print("SUCCESS: Stream is bit-identical. Total bytes: {}\n", .{offset});
}
