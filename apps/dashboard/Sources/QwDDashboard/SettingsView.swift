import SwiftUI

struct SettingsView: View {
    @AppStorage("qwd_thread_count")    private var threadCount: Int = 4
    @AppStorage("qwd_max_memory")      private var maxMemory: Double = 1024
    @AppStorage("qwd_execution_mode")  private var mode: ExecutionMode = .exact

    enum ExecutionMode: String, CaseIterable, Identifiable {
        case exact = "Exact"
        case fast  = "Fast (Heuristic)"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section("Engine Parameters") {
                Picker("Execution Mode", selection: $mode) {
                    ForEach(ExecutionMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.inline)
                
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
                LabeledContent("QwD Core", value: "v1.0.1 (Native ARM64)")
                LabeledContent("SIMD Acceleration", value: "Enabled (NEON/AVX2)")
                LabeledContent("Pipeline Architecture", value: "Phase Q Columnar")
            }
            
            Section {
                Button("Reset Defaults", role: .destructive) {
                    threadCount = 4
                    maxMemory = 1024
                    mode = .exact
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Global Settings")
        .frame(maxWidth: 600)
    }
}
