const std = @import("std");
const bam_reader = @import("bam_reader");

const alignment_stats_mod = @import("alignment_stats");
const mapq_dist_mod = @import("mapq_dist");
const coverage_mod = @import("coverage");
const error_rate_mod = @import("error_rate");
const soft_clip_mod = @import("soft_clip");

test "BAM Analytics - Alignment Stats" {
    var stage = alignment_stats_mod.AlignmentStatsStage{};
    var record = bam_reader.AlignmentRecord{
        .flag = 0,
        .reference_id = 1,
        .position = 100,
        .mapping_quality = 60,
        .cigar = "10M",
        .sequence = "ACGTACGTAC",
        .quality = "IIIIIIIIII",
        .template_length = 0,
    };
    
    _ = try alignment_stats_mod.AlignmentStatsStage.process(&stage, &record);
    try alignment_stats_mod.AlignmentStatsStage.finalize(&stage);
    
    try std.testing.expectEqual(@as(usize, 1), stage.mapped_reads);
    try std.testing.expectEqual(@as(f64, 60.0), stage.mean_mapping_quality);
}

test "BAM Analytics - MAPQ Distribution" {
    var stage = mapq_dist_mod.MapqDistributionStage{};
    var record = bam_reader.AlignmentRecord{
        .flag = 0,
        .reference_id = 1,
        .position = 100,
        .mapping_quality = 60,
        .cigar = "10M",
        .sequence = "ACGT",
        .quality = "IIII",
        .template_length = 0,
    };
    _ = try mapq_dist_mod.MapqDistributionStage.process(&stage, &record);
    
    try std.testing.expectEqual(@as(usize, 1), stage.histogram[60]);
}

test "BAM Analytics - Coverage" {
    var stage = coverage_mod.CoverageStage.init(100);
    var record = bam_reader.AlignmentRecord{
        .flag = 0,
        .reference_id = 1,
        .position = 10,
        .mapping_quality = 60,
        .cigar = "10M",
        .sequence = "ACGTACGTAC",
        .quality = "IIIIIIIIII",
        .template_length = 0,
    };
    _ = try coverage_mod.CoverageStage.process(&stage, &record);
    try coverage_mod.CoverageStage.finalize(&stage);
    
    try std.testing.expectEqual(@as(f64, 0.1), stage.coverage_estimate);
}

test "BAM Analytics - Error Rate" {
    var stage = error_rate_mod.ErrorRateStage{};
    var record = bam_reader.AlignmentRecord{
        .flag = 0,
        .reference_id = 1,
        .position = 10,
        .mapping_quality = 60,
        .cigar = "9M1I",
        .sequence = "ACGTACGTAC",
        .quality = "IIIIIIIIII",
        .template_length = 0,
    };
    _ = try error_rate_mod.ErrorRateStage.process(&stage, &record);
    try error_rate_mod.ErrorRateStage.finalize(&stage);
    
    try std.testing.expectEqual(@as(usize, 1), stage.mismatches);
    try std.testing.expectEqual(@as(usize, 9), stage.aligned_bases);
}

test "BAM Analytics - Soft Clipping" {
    var stage = soft_clip_mod.SoftClipStage{};
    var record = bam_reader.AlignmentRecord{
        .flag = 0,
        .reference_id = 1,
        .position = 10,
        .mapping_quality = 60,
        .cigar = "8M2S",
        .sequence = "ACGTACGTAC",
        .quality = "IIIIIIIIII",
        .template_length = 0,
    };
    _ = try soft_clip_mod.SoftClipStage.process(&stage, &record);
    
    try std.testing.expectEqual(@as(usize, 1), stage.soft_clipped_reads);
    try std.testing.expectEqual(@as(usize, 2), stage.soft_clipped_bases);
}
