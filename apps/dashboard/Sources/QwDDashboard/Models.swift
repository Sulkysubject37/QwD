import Foundation

// ─────────────────────────────────────────────
// QwD Model Schema — Matches core/schemas/
// ─────────────────────────────────────────────

public struct QCReport: Codable {
    public let version: String
    public let thread_count: Int
    public let read_count: Int
    public let stages: QCStages
}

public struct QCStages: Codable {
    public let basic_stats: BasicStats?
    public let gc_distribution: GCDistribution?
    public let length_distribution: LengthDistribution?
    public let n_statistics: NStatistics?
    public let entropy: EntropyStats?
    public let duplication: DuplicationStats?
    public let overrepresented: OverrepresentedStats?
    public let trim: TrimStats?
    public let filter: FilterStats?
    
    // BAM-specific stages
    public let alignment_stats: AlignmentStats?
    public let coverage: CoverageStats?
    public let error_rate_stats: ErrorRateStats?
    public let soft_clipping: SoftClippingStats?
    public let mapq_distribution: MapqDistribution?
    public let insert_size: InsertSizeStats?
}

public struct AlignmentStats: Codable {
    public let total_records: Int
    public let mapped_reads: Int
    public let unmapped_reads: Int
    public let mean_mapq: Double
}

public struct CoverageStats: Codable {
    public let aligned_bases: Int
    public let reference_length: Int
    public let coverage_estimate: Double
}

public struct ErrorRateStats: Codable {
    public let aligned_bases: Int
    public let mismatches: Int
    public let error_rate: Double
}

public struct SoftClippingStats: Codable {
    public let soft_clipped_reads: Int
    public let soft_clipped_bases: Int
}

public struct MapqDistribution: Codable {
    public let histogram: [Int]
}

public struct InsertSizeStats: Codable {
    public let pairs_analyzed: Int
    public let min_insert: Int
    public let max_insert: Int
    public let mean_insert: Double
    public let histogram_500bp_bins: [Int]
}

public struct BasicStats: Codable {
    public let total_reads: Int
    public let total_bases: Int
    public let min_length: Int
    public let max_length: Int
    public let mean_length: Double
    public let integrity_violations: Int?
}

public struct GCDistribution: Codable {
    public let bins: [Int]
}

public struct LengthDistribution: Codable {
    public let bins: [Int]
}

public struct NStatistics: Codable {
    public let n10: Int
    public let n50: Int
    public let n90: Int
}

public struct EntropyStats: Codable {
    public let mean_entropy: Double?
    public let total_entropy_sum: Double? // Internal consistency
    public let low_complexity_reads: Int
    
    // Fallback for different JSON versions
    public var entropy: Double {
        mean_entropy ?? 0.0
    }
}

public struct DuplicationStats: Codable {
    public let total_reads: Int
    public let duplicate_reads: Int
    public let duplication_ratio: Double
}

public struct OverrepresentedStats: Codable, Identifiable {
    public var id: String { most_frequent }
    public let unique_sequences: Int
    public let most_frequent: String
    public let most_frequent_count: Int
}

public struct TrimStats: Codable {
    public let reads_seen: Int
    public let reads_trimmed: Int
}

public struct FilterStats: Codable {
    public let reads_seen: Int
    public let reads_passed: Int
    public let reads_filtered: Int
}

// ─────────────────────────────────────────────
// Pipeline Configuration (For Engine Injection)
// ─────────────────────────────────────────────

public struct BioPipelineConfig: Encodable {
    public var pipeline: [String]
    public var mode: String
    public var trim_front: Int
    public var trim_tail: Int
    public var min_quality: Double
    public var adapter_sequence: String?
    
    public init(
        pipeline: [String] = ["basic_stats", "per_base_quality", "gc_distribution", "length_distribution", "duplication"],
        mode: String = "EXACT",
        trim_front: Int = 0,
        trim_tail: Int = 0,
        min_quality: Double = 0.0,
        adapter_sequence: String? = nil
    ) {
        self.pipeline = pipeline
        self.mode = mode
        self.trim_front = trim_front
        self.trim_tail = trim_tail
        self.min_quality = min_quality
        self.adapter_sequence = adapter_sequence
    }
}

// ─────────────────────────────────────────────
// Extensions
// ─────────────────────────────────────────────

extension Notification.Name {
    public static let qwdOpenFile = Notification.Name("qwdOpenFile")
}
