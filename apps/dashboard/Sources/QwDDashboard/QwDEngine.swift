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
    
    // User Preferences (synced with AppStorage keys in SettingsView)
    private let threadCountKey = "qwd_thread_count"
    private let analysisModeKey = "qwd_analysis_mode"
    private let gzipModeKey = "qwd_gzip_mode"
    
    private init() {}
    
    @MainActor
    public func runQC(on path: String) async {
        self.isRunning = true
        self.errorMessage = nil
        
        // Fetch current settings from UserDefaults
        let threads = UserDefaults.standard.integer(forKey: threadCountKey) == 0 ? 4 : UserDefaults.standard.integer(forKey: threadCountKey)
        let modeString = UserDefaults.standard.string(forKey: analysisModeKey) ?? "Exact (Deterministic)"
        let gzipModeString = UserDefaults.standard.string(forKey: gzipModeKey) ?? "Auto (Detect)"
        
        // Map strings to C-API integers
        let modeInt: Int32 = modeString.contains("Approx") ? 1 : 0
        let gzipModeInt: Int32 = switch gzipModeString {
            case let s where s.contains("SIMD"): 1
            case let s where s.contains("Chunked"): 2
            case let s where s.contains("Compat"): 3
            default: 0
        }
        
        defer { self.isRunning = false }
        
        // Removed 'await' from the detached closure body since it's synchronous
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            return path.withCString { cPath in
                // qwd_fastq_qc_ex is now exposed in CQwD.h
                let resPtr = qwd_fastq_qc_ex(cPath, Int32(threads), modeInt, gzipModeInt)
                
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
        } catch {
            self.errorMessage = "Failed to parse Engine output: \(error.localizedDescription)"
            print("JSON Error: \(error)")
            #if DEBUG
            print("Raw JSON: \(jsonString)")
            #endif
        }
    }
}
