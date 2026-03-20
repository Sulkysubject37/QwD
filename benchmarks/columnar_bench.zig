const std = @import("std");
const fastq_block = @import("fastq_block");
const column_ops = @import("column_ops");
const bitplanes = @import("bitplanes");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const read_count = 1024;
    const max_len = 300;
    
    var block = try fastq_block.FastqColumnBlock.init(allocator, read_count, max_len);
    defer block.deinit();

    // Fill with dummy data
    for (0..read_count) |i| {
        var seq: [300]u8 = undefined;
        var qual: [300]u8 = undefined;
        @memset(&seq, 'G');
        @memset(&qual, 'I');
        _ = block.addRead(&seq, &qual);
        _ = i;
    }

    std.debug.print("Benchmarking Columnar Ops ({d} reads, {d} bp)...\n", .{read_count, max_len});

    // 1. Column GC Count (SIMD)
    var timer = try std.time.Timer.start();
    var total_gc: usize = 0;
    for (0..1000) |_| {
        total_gc = 0;
        for (0..max_len) |col| {
            total_gc += column_ops.countGcColumn(block.bases[col], block.read_count);
        }
    }
    const gc_time = timer.read();
    std.debug.print("Column GC (SIMD): {d} ns\n", .{gc_time / 1000});

    // 2. Bitplane GC Count (Fused)
    var bp = try bitplanes.Bitplanes.init(allocator, read_count, max_len);
    defer bp.deinit();
    
    timer = try std.time.Timer.start();
    for (0..1000) |_| {
        bp.fromColumnBlock(&block);
        _ = bp.computeFused(block.read_count);
    }
    const bp_time = timer.read();
    std.debug.print("Bitplane Fused:   {d} ns\n", .{bp_time / 1000});
}
