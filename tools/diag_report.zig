const std = @import("std");
const pipeline_mod = @import("pipeline");
const pipeline_config = @import("pipeline_config");
const fastq_block = @import("fastq_block");
const bitplanes = @import("bitplanes");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    std.debug.print("[Diag] Initializing Pipeline...\n", .{});

    const config = pipeline_config.PipelineConfig.default();
    var pipeline = pipeline_mod.Pipeline.init(allocator, config);
    try pipeline.addDefaultStages();
    defer pipeline.deinit();

    std.debug.print("[Diag] Mocking data...\n", .{});
    var block = try fastq_block.FastqColumnBlock.init(allocator, 1024, 150);
    defer block.deinit();
    
    // Add one mock read
    const seq = "ATGC" ** 25; // 100bp
    const qual = "I" ** 100;
    block.read_lengths[0] = 100;
    for (0..100) |i| {
        block.bases[i][0] = seq[i];
        block.qualities[i][0] = qual[i] - 33;
    }
    block.read_count = 1;
    block.active_max_len = 100;

    std.debug.print("[Diag] Processing block...\n", .{});
    var bp_core = try bitplanes.BitplaneCore.init(allocator, 150, 1024);
    defer bp_core.deinit();
    bp_core.fromColumnBlock(&block);

    for (0..pipeline.stage_count) |i| {
        _ = try pipeline.stages[i].processBitplanes(&bp_core, &block);
    }
    pipeline.read_count = 1;

    std.debug.print("[Diag] Finalizing...\n", .{});
    try pipeline.finalize();

    std.debug.print("[Diag] Generating JSON...\n", .{});
    const report = try pipeline.reportJsonAlloc(allocator);
    defer allocator.free(report);

    std.debug.print("[Diag] Output result:\n{s}\n", .{report});
    std.debug.print("[Diag] Done.\n", .{});
}
