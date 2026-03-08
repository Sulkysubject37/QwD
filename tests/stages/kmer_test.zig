const std = @import("std");
const parser = @import("parser");
const kmer_mod = @import("kmer");

test "k-mer Stage Test" {
    const allocator = std.testing.allocator;
    var kmer_stage = try kmer_mod.KmerStage.init(allocator, 2);
    defer kmer_stage.deinit();

    var read = parser.Read{
        .id = "r1",
        .seq = "ACGT", // k-mers: AC, CG, GT
        .qual = "IIII",
    };

    _ = try kmer_mod.KmerStage.process(&kmer_stage, &read);
    try kmer_mod.KmerStage.finalize(&kmer_stage);

    // AC: A=0, C=1 -> index 01 (1)
    // CG: C=1, G=2 -> index 12 (6)
    // GT: G=2, T=3 -> index 23 (11)

    try std.testing.expectEqual(@as(u64, 1), kmer_stage.counts[1]);
    try std.testing.expectEqual(@as(u64, 1), kmer_stage.counts[6]);
    try std.testing.expectEqual(@as(u64, 1), kmer_stage.counts[11]);
    try std.testing.expectEqual(@as(u64, 3), kmer_stage.total_kmers);
}
