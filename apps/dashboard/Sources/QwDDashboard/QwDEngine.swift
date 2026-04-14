import Foundation
import CQwD
import SwiftUI

public enum QwDError: Error {
    case fileNotFound
    case executionFailed(String)
    case parsingFailed
}

@MainActor
@Observable
public final class QwDEngine {
    public static let shared = QwDEngine()
    
    public var isRunning: Bool = false
    public var lastReport: QCReport? = nil
    public var errorMessage: String? = nil
    
    // Track selected file path for the 2-step setup process
    public var selectedFilePath: String? = nil
    
    // User Preferences Keys
    private let threadCountKey = "qwd_thread_count"
    private let analysisModeKey = "qwd_analysis_mode"
    
    // Biological Keys
    private let trimFrontKey = "qwd_trim_front"
    private let trimTailKey = "qwd_trim_tail"
    private let minQualityKey = "qwd_min_quality"
    private let adapterSeqKey = "qwd_adapter_sequence"
    private let enableTrimmingKey = "qwd_enable_trimming"
    private let enableFilteringKey = "qwd_enable_filtering"
    
    private init() {}
    
    @MainActor
    public func runQC(on path: String? = nil) async {
        guard let targetPath = path ?? self.selectedFilePath else {
            self.errorMessage = "No file selected."
            return
        }
        
        self.isRunning = true
        self.errorMessage = nil
        
        // Fetch settings directly from UserDefaults
        let threads = UserDefaults.standard.integer(forKey: threadCountKey) == 0 ? 4 : UserDefaults.standard.integer(forKey: threadCountKey)
        let modeString = UserDefaults.standard.string(forKey: analysisModeKey) ?? "Exact (Deterministic)"
        
        // Biological Parameters
        let enableTrimming = UserDefaults.standard.bool(forKey: enableTrimmingKey)
        let enableFiltering = UserDefaults.standard.bool(forKey: enableFilteringKey)
        
        let trimFront = UserDefaults.standard.integer(forKey: trimFrontKey)
        let trimTail = UserDefaults.standard.integer(forKey: trimTailKey)
        let minQual = UserDefaults.standard.double(forKey: minQualityKey)
        let adapterSeq = UserDefaults.standard.string(forKey: adapterSeqKey) ?? ""
        
        let modeInt: Int32 = modeString.contains("Approx") ? 1 : 0
        
        defer { self.isRunning = false }
        
        let isBam = targetPath.lowercased().hasSuffix(".bam")
        
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            if isBam {
                return targetPath.withCString { cPath in
                    let resPtr = qwd_bam_stats(cPath, Int32(threads))
                    guard let validPtr = resPtr else { return nil }
                    defer { qwd_free_string(validPtr) }
                    return String(cString: validPtr)
                }
            } else {
                // Construct JSON Config for FASTQ
                var pipeline = ["basic_stats", "per_base_quality", "gc_distribution", "length_distribution", "duplication"]
                
                if enableTrimming {
                    pipeline.insert("trim", at: 1)
                }
                if enableFiltering {
                    pipeline.append("filter")
                }
                
                let config = BioPipelineConfig(
                    pipeline: pipeline,
                    mode: modeInt == 1 ? "APPROX" : "EXACT",
                    trim_front: enableTrimming ? trimFront : 0,
                    trim_tail: enableTrimming ? trimTail : 0,
                    min_quality: enableFiltering ? minQual : 0.0,
                    adapter_sequence: (enableTrimming && !adapterSeq.isEmpty) ? adapterSeq : nil
                )
                
                guard let configData = try? JSONEncoder().encode(config),
                      let configJSON = String(data: configData, encoding: .utf8) else {
                    return nil
                }
                
                return targetPath.withCString { cPath in
                    return configJSON.withCString { cJson in
                        let resPtr = qwd_run_json_config(cJson, cPath)
                        guard let validPtr = resPtr else { return nil }
                        defer { qwd_free_string(validPtr) }
                        return String(cString: validPtr)
                    }
                }
            }
        }.value
        
        guard let jsonString = result, let data = jsonString.data(using: .utf8) else {
            self.errorMessage = "Failed to communicate with QwD Engine."
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let report = try decoder.decode(QCReport.self, from: data)
            self.lastReport = report
            self.selectedFilePath = nil 
        } catch {
            self.errorMessage = "Failed to parse Engine output: \(error.localizedDescription)"
            print("JSON Error: \(error)")
        }
    }
}
