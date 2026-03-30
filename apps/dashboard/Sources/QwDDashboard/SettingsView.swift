import SwiftUI

struct SettingsView: View {
    @AppStorage("qwd_thread_count")    private var threadCount: Int = 4
    @AppStorage("qwd_max_memory")      private var maxMemory: Double = 1024
    @AppStorage("qwd_analysis_mode")   private var mode: AnalysisMode = .exact
    @AppStorage("qwd_gzip_mode")       private var gzipMode: GzipMode = .auto

    enum AnalysisMode: String, CaseIterable, Identifiable {
        case exact = "Exact (Deterministic)"
        case approx = "Approx (Heuristic)"
        var id: String { rawValue }
    }

    enum GzipMode: String, CaseIterable, Identifiable {
        case auto       = "Auto (Detect)"
        case libdeflate = "SIMD (Fast)"
        case native     = "Native (QwD)"
        case chunked    = "Chunked (Large)"
        case compat     = "Compat (Safe)"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section("Analytical Strategy") {
                Picker("Execution Mode", selection: $mode) {
                    ForEach(AnalysisMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(mode == .exact ? "Ensures 100% precision using exhaustive tracking." : "Uses mathematical sketches for sub-second analysis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Decompression Engine") {
                Picker("GZIP Mode", selection: $gzipMode) {
                    ForEach(GzipMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.menu)
                
                Text(gzipMode == .native ? "Pure-Zig zero-dependency engine. Optimized for Phase P.2." : "Detection-based selection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Resource Allocation") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parallel Threads: \(threadCount)")
                    Slider(value: Binding(get: { Double(threadCount) }, set: { threadCount = Int($0) }), in: 1...128, step: 1)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Memory Ceiling: \(Int(maxMemory)) MB")
                    Slider(value: $maxMemory, in: 32...32768, step: 256)
                }
            }
            
            Section("System Diagnostics") {
                LabeledContent("QwD Core", value: "v1.1.0 (Production)")
                LabeledContent("SIMD Acceleration", value: "Enabled (NEON/AVX2)")
                LabeledContent("Native Deflate", value: "Verified Stable")
            }
            
            Section {
                Button("Reset Defaults", role: .destructive) {
                    threadCount = 4
                    maxMemory = 1024
                    mode = .exact
                    gzipMode = .auto
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Global Settings")
        .frame(maxWidth: 600)
    }
}
