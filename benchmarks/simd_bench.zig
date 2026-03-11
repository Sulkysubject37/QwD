const std = @import("std");
const simd = @import("simd_ops");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const size = 100 * 1024 * 1024; // 100MB
    const buffer = try allocator.alloc(u8, size);
    defer allocator.free(buffer);
    
    var prng = std.rand.DefaultPrng.init(42);
    
    // Test 1: GC Counting
    prng.random().bytes(buffer);
    for (buffer) |*b| {
        b.* = "ACGTacgt"[b.* % 8];
    }

    std.debug.print("--- GC Counting Benchmark (100MB) ---\n", .{});

    var timer = try std.time.Timer.start();
    const gc_scalar = simd.countGcScalar(buffer);
    const t_gc_scalar = timer.read();
    
    timer.reset();
    const gc_simd = simd.countGcSimd(buffer);
    const t_gc_simd = timer.read();

    std.debug.print("Scalar: {d:>12} ns (GC count: {d})\n", .{ t_gc_scalar, gc_scalar });
    std.debug.print("SIMD:   {d:>12} ns (GC count: {d})\n", .{ t_gc_simd, gc_simd });
    std.debug.print("Speedup: {d:.2}x\n\n", .{ @as(f64, @floatFromInt(t_gc_scalar)) / @as(f64, @floatFromInt(t_gc_simd)) });

    // Test 2: PHRED Quality Summing
    prng.random().bytes(buffer);
    for (buffer) |*b| {
        b.* = 33 + (b.* % 40); // Standard PHRED range
    }

    std.debug.print("--- PHRED Quality Summing Benchmark (100MB) ---\n", .{});

    timer.reset();
    const phred_scalar = simd.sumPhredScalar(buffer);
    const t_phred_scalar = timer.read();
    
    timer.reset();
    const phred_simd = simd.sumPhredSimd(buffer);
    const t_phred_simd = timer.read();

    std.debug.print("Scalar: {d:>12} ns (Sum: {d})\n", .{ t_phred_scalar, phred_scalar });
    std.debug.print("SIMD:   {d:>12} ns (Sum: {d})\n", .{ t_phred_simd, phred_simd });
    std.debug.print("Speedup: {d:.2}x\n", .{ @as(f64, @floatFromInt(t_phred_scalar)) / @as(f64, @floatFromInt(t_phred_simd)) });
}
