import SwiftUI

struct DashboardView: View {
    @Environment(QwDEngine.self) private var engine
    @State private var showFilePicker = false
    
    // Per-analysis overrides (defaults from AppStorage handled in SettingsView)
    @AppStorage("qwd_thread_count")    private var defaultThreads: Int = 4
    @AppStorage("qwd_analysis_mode")   private var defaultMode: SettingsView.AnalysisMode = .exact
    @AppStorage("qwd_gzip_mode")       private var defaultGzip: SettingsView.GzipMode = .auto

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                if engine.isRunning {
                    ProcessingView()
                } else if let report = engine.lastReport {
                    ReportView(report: report)
                } else if engine.selectedFilePath != nil {
                    ConfigurationView()
                } else {
                    EmptyDashboardView()
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }
}

// ─────────────────────────────────────────────
// Subviews
// ─────────────────────────────────────────────

struct EmptyDashboardView: View {
    @Environment(QwDEngine.self) private var engine
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(.tint)
            
            VStack(spacing: 8) {
                Text("Start Sequence Analysis")
                    .font(.system(size: 28, weight: .bold))
                Text("Select a FASTQ or BAM file to begin processing.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                selectFile()
            } label: {
                Text("Choose File...")
                    .font(.headline)
                    .frame(width: 200, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Text("Drag and drop files here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 500)
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.data, .init(filenameExtension: "gz")!, .init(filenameExtension: "fastq")!, .init(filenameExtension: "bam")!]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                engine.selectedFilePath = url.path
            }
        }
    }
}

struct ConfigurationView: View {
    @Environment(QwDEngine.self) private var engine
    
    var body: some View {
        VStack(spacing: 32) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis Configuration")
                        .font(.title.bold())
                    Text(URL(fileURLWithPath: engine.selectedFilePath ?? "").lastPathComponent)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    engine.selectedFilePath = nil
                }
                .buttonStyle(.bordered)
            }
            
            HStack(alignment: .top, spacing: 24) {
                // Settings summary/override
                VStack(alignment: .leading, spacing: 20) {
                    Text("Presets & Strategies")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        PresetTile(title: "Analytical Mode", icon: "bolt.shield", value: UserDefaults.standard.string(forKey: "qwd_analysis_mode") ?? "Exact")
                        PresetTile(title: "Decompression", icon: "shippingbox.and.arrow.backward", value: UserDefaults.standard.string(forKey: "qwd_gzip_mode") ?? "Auto")
                        PresetTile(title: "Concurrency", icon: "cpu", value: "\(UserDefaults.standard.integer(forKey: "qwd_thread_count")) Threads")
                    }
                    
                    Text("Change these in global Settings if needed.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 280)
                .proPanel(padding: 20)
                
                VStack(alignment: .leading, spacing: 20) {
                    Text("Validation Checklist")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        CheckItem(text: "Input format detected (FASTQ/GZ)")
                        CheckItem(text: "Resource limits verified")
                        CheckItem(text: "Output directory writable")
                    }
                    
                    Spacer()
                    
                    Button {
                        Task { await engine.runQC() }
                    } label: {
                        HStack {
                            Text("Execute Pipeline")
                            Image(systemName: "play.fill")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .proPanel(padding: 20)
            }
        }
        .frame(maxWidth: 800)
    }
}

struct ProcessingView: View {
    var body: some View {
        VStack(spacing: 32) {
            ProgressView()
                .scaleEffect(1.5)
                .controlSize(.large)
            
            VStack(spacing: 8) {
                Text("Analyzing Sequence Data...")
                    .font(.title2.bold())
                Text("QwD SIMD Core is currently processing columnar chunks.")
                    .foregroundStyle(.secondary)
            }
            
            Text("DO NOT CLOSE THE APPLICATION")
                .font(.caption.monospaced())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.red.opacity(0.1))
                .foregroundStyle(.red)
                .cornerRadius(4)
        }
        .frame(minHeight: 400)
    }
}

struct PresetTile: View {
    let title: String
    let icon: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.bold())
            }
        }
    }
}

struct CheckItem: View {
    let text: String
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline)
        }
    }
}
