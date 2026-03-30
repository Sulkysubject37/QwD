import Foundation

// ─────────────────────────────────────────────
// QwD Model Schema — Matches core/schemas/
// ─────────────────────────────────────────────

public struct QCReport: Codable {
    public let version: String
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
}

public struct BasicStats: Codable {
    public let total_reads: Int
    public let total_bases: Int
    public let min_length: Int
    public let max_length: Int
    public let mean_length: Double
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

// ─────────────────────────────────────────────
// Extensions
// ─────────────────────────────────────────────

extension Notification.Name {
    public static let qwdOpenFile = Notification.Name("qwdOpenFile")
}
