const std = @import("std");
const parser = @import("parser");
const pipeline_mod = @import("pipeline");

test "Pipeline Integration Test: trim -> filter -> qc" {
    const allocator = std.testing.allocator;
    var pipeline = pipeline_mod.Pipeline.init(allocator);
    defer pipeline.deinit();

    try pipeline.addStageByName("trim");   // Default adapter AGCT
    try pipeline.addStageByName("filter"); // Default min_qual 20
    try pipeline.addStageByName("qc");

    // Read 1: Should be trimmed and pass
    const read1 = parser.Read{
        .id = "r1",
        .seq = "AAAAAGCT",
        .qual = "IIIIIIII", // Qual 40
    };
    try pipeline.run(read1);

    // Read 2: Should be filtered (low quality)
    const read2 = parser.Read{
        .id = "r2",
        .seq = "CCCCCCCC",
        .qual = "!!!!!!!!", // Qual 0
    };
    try pipeline.run(read2);

    try pipeline.finalize();

    // Verification
    try std.testing.expectEqual(@as(usize, 2), pipeline.scheduler.read_count);
}
