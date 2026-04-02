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
    
    // User Preferences (synced with AppStorage keys in SettingsView)
    private let threadCountKey = "qwd_thread_count"
    private let analysisModeKey = "qwd_analysis_mode"
    private let gzipModeKey = "qwd_gzip_mode"
    
    private init() {}
    
    @MainActor
    public func runQC(on path: String? = nil) async {
        guard let targetPath = path ?? self.selectedFilePath else {
            self.errorMessage = "No file selected."
            return
        }
        
        self.isRunning = true
        self.errorMessage = nil
        
        // Fetch current settings from UserDefaults
        let threads = UserDefaults.standard.integer(forKey: threadCountKey) == 0 ? 4 : UserDefaults.standard.integer(forKey: threadCountKey)
        let modeString = UserDefaults.standard.string(forKey: analysisModeKey) ?? "Exact (Deterministic)"
        let gzipModeString = UserDefaults.standard.string(forKey: gzipModeKey) ?? "Auto (Detect)"
        
        // Map strings to C-API integers
        let modeInt: Int32 = modeString.contains("Approx") ? 1 : 0
        let gzipModeInt: Int32 = switch gzipModeString {
            case let s where s.contains("Native"): 1
            case let s where s.contains("SIMD"): 2
            case let s where s.contains("Chunked"): 3
            case let s where s.contains("Compat"): 4
            default: 0
        }
        defer { self.isRunning = false }
        
        let isBam = targetPath.lowercased().hasSuffix(".bam")
        
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            return targetPath.withCString { cPath in
                let resPtr = if isBam {
                    qwd_bam_stats(cPath, Int32(threads))
                } else {
                    qwd_fastq_qc_ex(cPath, Int32(threads), modeInt, gzipModeInt)
                }
                guard let validPtr = resPtr else { return nil }
                defer { qwd_free_string(validPtr) }
                return String(cString: validPtr)
            }
        }.value
        
        guard let jsonString = result, let data = jsonString.data(using: String.Encoding.utf8) else {
            self.errorMessage = "Failed to communicate with QwD Engine."
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let report = try decoder.decode(QCReport.self, from: data)
            self.lastReport = report
            self.selectedFilePath = nil // Reset after success
        } catch {
            self.errorMessage = "Failed to parse Engine output: \(error.localizedDescription)"
            print("JSON Error: \(error)")
        }
    }
}
