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
    private let executionModeKey = "qwd_execution_mode"
    
    private init() {}
    
    @MainActor
    public func runQC(on path: String) async {
        self.isRunning = true
        self.errorMessage = nil
        
        // Fetch current settings from UserDefaults
        let threads = UserDefaults.standard.integer(forKey: threadCountKey) == 0 ? 4 : UserDefaults.standard.integer(forKey: threadCountKey)
        let modeString = UserDefaults.standard.string(forKey: executionModeKey) ?? "Exact"
        let isFast = modeString == "Fast (Heuristic)"
        
        defer { self.isRunning = false }
        
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            return path.withCString { cPath in
                let resPtr: UnsafePointer<Int8>?
                
                if isFast {
                    resPtr = qwd_fastq_qc_fast(cPath, Int32(threads))
                } else {
                    resPtr = qwd_fastq_qc(cPath)
                }
                
                guard let validPtr = resPtr else { return nil }
                defer { qwd_free_string(validPtr) }
                return String(cString: validPtr)
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
        } catch {
            self.errorMessage = "Failed to parse Engine output: \(error.localizedDescription)"
            print("JSON Error: \(error)")
            #if DEBUG
            print("Raw JSON: \(jsonString)")
            #endif
        }
    }
}
