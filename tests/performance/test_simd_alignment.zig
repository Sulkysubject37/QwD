const std = @import("std");
const vertical_scanner = @import("../../core/simd/vertical_scanner.zig");

test "FastqScanner SIMD vs Scalar alignment" {
    const allocator = std.testing.allocator;
    
    // 1. Generate a test buffer with varied line lengths and content
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    const target_size = 4096;
    var rng = std.rand.DefaultPrng.init(42);
    const random = rng.random();
    
    while (buffer.items.len < target_size) {
        const line_len = random.uintLessThan(usize, 200) + 1;
        for (0..line_len) |_| {
            try buffer.append(random.uintAtMost(u8, 127));
        }
        try buffer.append('\n');
    }
    
    const data = buffer.items;
    
    // 2. Run Scalar Scan
    var scalar_indices = std.ArrayList(usize).init(allocator);
    defer scalar_indices.deinit();
    for (data, 0..) |byte, idx| {
        if (byte == '\n') try scalar_indices.append(idx);
    }
    
    // 3. Run SIMD Scan
    var simd_indices_buf = try allocator.alloc(usize, scalar_indices.items.len + 32);
    defer allocator.free(simd_indices_buf);
    
    var scan_res = vertical_scanner.FastqScanner.ScanResult{
        .indices = simd_indices_buf,
        .count = 0,
    };
    vertical_scanner.FastqScanner.scanNewlinesSIMD(data, &scan_res);
    
    // 4. Compare
    try std.testing.expectEqual(scalar_indices.items.len, scan_res.count);
    
    for (scalar_indices.items, 0..) |expected, i| {
        if (expected != scan_res.indices[i]) {
            std.debug.print("Mismatch at index {d}: expected {d}, got {d}\n", .{i, expected, scan_res.indices[i]});
            // Show context
            const start = if (expected > 10) expected - 10 else 0;
            const end = if (expected + 10 < data.len) expected + 10 else data.len;
            std.debug.print("Context: '{s}'\n", .{data[start..end]});
            try std.testing.expect(false);
        }
    }
}
