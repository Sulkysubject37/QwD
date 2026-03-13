const std = @import("std");
const parser = @import("parser");

// We import the modules to test them
const entropy_mod = @import("qc_entropy");
const kmer_spectrum_mod = @import("kmer_spectrum");
const gc_distribution_mod = @import("gc_distribution");
const duplication_mod = @import("duplication");
const adapter_detection_mod = @import("qc_adapter_detect");

test "FASTQ QC - Entropy" {
    var stage = entropy_mod.EntropyStage{};
    var read = parser.Read{ .id = "1", .seq = "AAAA", .qual = "IIII" };
    _ = try entropy_mod.EntropyStage.process(&stage, &read);
    try entropy_mod.EntropyStage.finalize(&stage);
    try std.testing.expect(stage.low_complexity_reads == 1);
}

test "FASTQ QC - K-mer Spectrum" {
    const allocator = std.testing.allocator;
    var stage = try kmer_spectrum_mod.KmerSpectrumStage.init(allocator);
    defer stage.deinit();
    
    // k=5, sequence length 5 -> 1 kmer
    var read = parser.Read{ .id = "1", .seq = "ACGTA", .qual = "IIIII" };
    _ = try kmer_spectrum_mod.KmerSpectrumStage.process(&stage, &read);
    try kmer_spectrum_mod.KmerSpectrumStage.finalize(&stage);
    
    var total: u64 = 0;
    for (stage.counts) |c| total += c;
    try std.testing.expectEqual(@as(u64, 1), total);
}

test "FASTQ QC - GC Distribution" {
    var stage = gc_distribution_mod.GcDistributionStage{};
    // GC ratio = 0.5 (50%), bin = 5
    var read = parser.Read{ .id = "1", .seq = "GCAT", .qual = "IIII" };
    _ = try gc_distribution_mod.GcDistributionStage.process(&stage, &read);
    try gc_distribution_mod.GcDistributionStage.finalize(&stage);
    
    try std.testing.expectEqual(@as(usize, 1), stage.histogram[5]);
}

test "FASTQ QC - Duplication" {
    const allocator = std.testing.allocator;
    var stage = duplication_mod.DuplicationStage.init(allocator, false);
    defer stage.deinit();
    
    var read1 = parser.Read{ .id = "1", .seq = "ACGT", .qual = "IIII" };
    var read2 = parser.Read{ .id = "2", .seq = "ACGT", .qual = "IIII" };
    var read3 = parser.Read{ .id = "3", .seq = "TGCA", .qual = "IIII" };
    
    _ = try duplication_mod.DuplicationStage.process(&stage, &read1);
    _ = try duplication_mod.DuplicationStage.process(&stage, &read2);
    _ = try duplication_mod.DuplicationStage.process(&stage, &read3);
    try duplication_mod.DuplicationStage.finalize(&stage);
    
    try std.testing.expectEqual(@as(usize, 3), stage.total_reads);
    try std.testing.expectEqual(@as(usize, 1), stage.duplicate_reads);
}

test "FASTQ QC - Adapter Detection" {
    const allocator = std.testing.allocator;
    var stage = try adapter_detection_mod.AdapterDetectionStage.init(allocator);
    defer stage.deinit();
    
    // suffix length 20, we need seq >= 20
    var read = parser.Read{ .id = "1", .seq = "A" ** 20, .qual = "I" ** 20 };
    _ = try adapter_detection_mod.AdapterDetectionStage.process(&stage, &read);
    try adapter_detection_mod.AdapterDetectionStage.finalize(&stage);
    
    // all 8-mers in suffix A**20 will be AAAAAAAA (idx 0)
    // number of kmers = 20 - 8 + 1 = 13
    try std.testing.expectEqual(@as(u64, 13), stage.counts[0]);
}
