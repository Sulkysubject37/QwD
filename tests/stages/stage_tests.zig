const std = @import("std");
const parser = @import("parser");
const qc_mod = @import("qc");
const gc_mod = @import("gc");
const length_mod = @import("length");
const length_dist_mod = @import("length_dist");
const n50_mod = @import("n50");
const qual_decay_mod = @import("qual_decay");
const entropy_mod = @import("entropy");
const adapter_detect_mod = @import("adapter_detect");

test "QC Stage Test" {
    var qc = qc_mod.QcStage{};
    var read = parser.Read{
        .id = "r1",
        .seq = "ACGT",
        .qual = "IIII", // 'I' is PHRED 40
    };
    _ = try qc_mod.QcStage.process(&qc, &read);
    try qc_mod.QcStage.finalize(&qc);

    try std.testing.expectEqual(@as(usize, 1), qc.total_reads);
    try std.testing.expectEqual(@as(usize, 4), qc.total_bases);
    try std.testing.expectEqual(@as(f64, 40.0), qc.mean_quality);
}

test "GC Stage Test" {
    var gc = gc_mod.GcStage{};
    var read = parser.Read{
        .id = "r1",
        .seq = "ACGT",
        .qual = "IIII",
    };
    _ = try gc_mod.GcStage.process(&gc, &read);
    try gc_mod.GcStage.finalize(&gc);

    try std.testing.expectEqual(@as(f64, 0.5), gc.gc_ratio);
}

test "Length Stage Test" {
    var length = length_mod.LengthStage{};
    var reads = [_]parser.Read{
        .{ .id = "r1", .seq = "A" ** 10, .qual = "I" ** 10 },
        .{ .id = "r2", .seq = "A" ** 20, .qual = "I" ** 20 },
        .{ .id = "r3", .seq = "A" ** 30, .qual = "I" ** 30 },
    };

    for (0..reads.len) |i| {
        _ = try length_mod.LengthStage.process(&length, &reads[i]);
    }
    try length_mod.LengthStage.finalize(&length);

    try std.testing.expectEqual(@as(f64, 20.0), length.mean_length);
    try std.testing.expectEqual(@as(usize, 10), length.min_length);
    try std.testing.expectEqual(@as(usize, 30), length.max_length);
}

test "Entropy Stage Test" {
    var entropy_stage = entropy_mod.EntropyStage{};
    
    // Low complexity
    var read1 = parser.Read{
        .id = "r1",
        .seq = "AAAAAAAAAA",
        .qual = "IIIIIIIIII",
    };
    _ = try entropy_mod.EntropyStage.process(&entropy_stage, &read1);
    
    // High complexity
    var read2 = parser.Read{
        .id = "r2",
        .seq = "ACGTACGTAC",
        .qual = "IIIIIIIIII",
    };
    _ = try entropy_mod.EntropyStage.process(&entropy_stage, &read2);
    
    try entropy_mod.EntropyStage.finalize(&entropy_stage);
    
    try std.testing.expect(entropy_stage.low_complexity_reads >= 1);
}

test "N50 Stage Test" {
    var n50_stage = n50_mod.N50Stage{};
    var read1 = parser.Read{ .id = "r1", .seq = "A" ** 100, .qual = "I" ** 100 };
    var read2 = parser.Read{ .id = "r2", .seq = "A" ** 200, .qual = "I" ** 200 };
    var read3 = parser.Read{ .id = "r3", .seq = "A" ** 300, .qual = "I" ** 300 };
    
    _ = try n50_mod.N50Stage.process(&n50_stage, &read1);
    _ = try n50_mod.N50Stage.process(&n50_stage, &read2);
    _ = try n50_mod.N50Stage.process(&n50_stage, &read3);
    
    try n50_mod.N50Stage.finalize(&n50_stage);
    
    // Total = 600, 50% = 300. Read3 is 300. 300 >= 300. So N50 = 300.
    try std.testing.expectEqual(@as(usize, 300), n50_stage.n50);
}

test "Quality Decay Stage Test" {
    var qd_stage = qual_decay_mod.QualityDecayStage{};
    var read = parser.Read{
        .id = "r1",
        .seq = "ACGT",
        .qual = "IIII", // PHRED 40
    };
    _ = try qual_decay_mod.QualityDecayStage.process(&qd_stage, &read);
    try qual_decay_mod.QualityDecayStage.finalize(&qd_stage);
    
    try std.testing.expectEqual(@as(f64, 40.0), qd_stage.mean_quality[0]);
    try std.testing.expectEqual(@as(f64, 40.0), qd_stage.mean_quality[3]);
}
