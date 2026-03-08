const std = @import("std");
const parser = @import("parser");
const qc_mod = @import("qc");
const gc_mod = @import("gc");
const length_mod = @import("length");

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
