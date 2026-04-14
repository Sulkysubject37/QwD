import SwiftUI

struct DashboardView: View {
    @Environment(QwDEngine.self) private var engine
    @State private var showFilePicker = false
    
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
    
    // Persistent Storage (Used only for saving on Execute)
    @AppStorage("qwd_trim_front")       private var storeTrimFront: Int = 0
    @AppStorage("qwd_trim_tail")        private var storeTrimTail: Int = 0
    @AppStorage("qwd_min_quality")      private var storeMinQual: Double = 0.0
    @AppStorage("qwd_adapter_sequence")  private var storeAdapterSeq: String = ""
    @AppStorage("qwd_enable_trimming")   private var storeEnableTrimming: Bool = false
    @AppStorage("qwd_enable_filtering")  private var storeEnableFiltering: Bool = false
    
    // LOCAL STATE: Completely decoupled from persistent storage
    @State private var trimFront: Int = 0
    @State private var trimTail: Int = 0
    @State private var minQual: Double = 0.0
    @State private var adapterSeq: String = ""
    @State private var enableTrimming: Bool = false
    @State private var enableFiltering: Bool = false
    
    @FocusState private var isAdapterFocused: Bool
    
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
                // 1. Hardware & Strategy
                VStack(alignment: .leading, spacing: 20) {
                    Text("Hardware & Strategy")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        PresetTile(title: "Analytical Mode", icon: "bolt.shield", value: UserDefaults.standard.string(forKey: "qwd_analysis_mode") ?? "Exact")
                        PresetTile(title: "Decompression", icon: "shippingbox.and.arrow.backward", value: UserDefaults.standard.string(forKey: "qwd_gzip_mode") ?? "Auto")
                        
                        let tCount = UserDefaults.standard.integer(forKey: "qwd_thread_count")
                        PresetTile(title: "Concurrency", icon: "cpu", value: "\(tCount == 0 ? 4 : tCount) Threads")
                    }
                    .proPanel(padding: 16)
                    
                    Text("Global settings can be adjusted in the Settings menu.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 260)
                
                // 2. Biological Gates (ACTIVE CONTROLS)
                VStack(alignment: .leading, spacing: 20) {
                    Text("Biological Gates")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 24) {
                        // Trimming Section
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable Sequence Trimming", isOn: $enableTrimming)
                                .font(.subheadline.bold())
                                .toggleStyle(.switch)
                            
                            if enableTrimming {
                                VStack(spacing: 12) {
                                    BiologicalSlider(label: "5' Trim (Front)", value: Binding(get: { Double(trimFront) }, set: { trimFront = Int($0) }), range: 0...100, unit: "bp")
                                    BiologicalSlider(label: "3' Trim (Tail)", value: Binding(get: { Double(trimTail) }, set: { trimTail = Int($0) }), range: 0...100, unit: "bp")
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Adapter Sequence").font(.caption.bold()).foregroundStyle(.secondary)
                                        TextField("Enter DNA sequence...", text: $adapterSeq)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                            .autocorrectionDisabled(true)
                                            .focused($isAdapterFocused)
                                    }
                                }
                                .padding(.leading, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        
                        Divider()
                        
                        // Quality Filtering Section
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable Quality Filtering", isOn: $enableFiltering)
                                .font(.subheadline.bold())
                                .toggleStyle(.switch)
                            
                            if enableFiltering {
                                BiologicalSlider(label: "Min Mean Quality", value: $minQual, range: 0...40, unit: "Phred")
                                    .padding(.leading, 8)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .proPanel(padding: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isAdapterFocused = false // Dismiss keyboard/focus when clicking panel
                    }
                }
                
                // 3. Execution Column
                VStack(alignment: .leading, spacing: 20) {
                    Text("Status")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        CheckItem(text: "Format detected")
                        CheckItem(text: "Resources verified")
                        CheckItem(text: enableTrimming || enableFiltering ? "Gates active" : "Raw pass-through")
                    }
                    
                    Spacer()
                    
                    Button {
                        executeWithSaving()
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
                .frame(width: 220)
            }
        }
        .frame(maxWidth: 1000)
        .onAppear {
            // Load from persistent storage once
            trimFront = storeTrimFront
            trimTail = storeTrimTail
            minQual = storeMinQual
            adapterSeq = storeAdapterSeq
            enableTrimming = storeEnableTrimming
            enableFiltering = storeEnableFiltering
        }
    }
    
    private func executeWithSaving() {
        // 1. Persist local state back to AppStorage
        storeTrimFront = trimFront
        storeTrimTail = trimTail
        storeMinQual = minQual
        storeAdapterSeq = adapterSeq
        storeEnableTrimming = enableTrimming
        storeEnableFiltering = enableFiltering
        
        // 2. Run Engine
        Task { await engine.runQC() }
    }
}

struct BiologicalSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(value, specifier: "%.1f") \(unit)").font(.caption.monospaced())
            }
            Slider(value: $value, in: range, step: 0.5)
        }
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
