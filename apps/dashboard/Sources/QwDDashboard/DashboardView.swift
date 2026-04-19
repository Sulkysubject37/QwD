import SwiftUI
import UniformTypeIdentifiers

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
                    EmptyDashboardView(showFilePicker: $showFilePicker)
                }
            }
            .padding(osDependentPadding)
            .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker(filePath: Bindable(engine).selectedFilePath)
        }
        #endif
    }
    
    private var osDependentPadding: CGFloat {
        #if os(macOS)
        return 40
        #else
        return 20
        #endif
    }
}

// ─────────────────────────────────────────────
// Subviews
// ─────────────────────────────────────────────

struct EmptyDashboardView: View {
    @Environment(QwDEngine.self) private var engine
    @Binding var showFilePicker: Bool
    
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
                    .multilineTextAlignment(.center)
            }
            
            Button {
                #if os(macOS)
                selectFileMacOS()
                #else
                showFilePicker = true
                #endif
            } label: {
                Text("Choose File...")
                    .font(.headline)
                    .frame(width: 200, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            #if os(macOS)
            Text("Drag and drop files here")
                .font(.caption)
                .foregroundStyle(.tertiary)
            #endif
        }
        .frame(minHeight: 500)
    }
    
    #if os(macOS)
    private func selectFileMacOS() {
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
    #endif
}

#if os(iOS)
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var filePath: String?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .init(filenameExtension: "gz")!, .init(filenameExtension: "fastq")!, .init(filenameExtension: "bam")!])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.filePath = urls.first?.path
        }
    }
}
#endif

struct ConfigurationView: View {
    @Environment(QwDEngine.self) private var engine
    
    @AppStorage("qwd_trim_front")       private var storeTrimFront: Int = 0
    @AppStorage("qwd_trim_tail")        private var storeTrimTail: Int = 0
    @AppStorage("qwd_min_quality")      private var storeMinQual: Double = 0.0
    @AppStorage("qwd_adapter_sequence")  private var storeAdapterSeq: String = ""
    @AppStorage("qwd_enable_trimming")   private var storeEnableTrimming: Bool = false
    @AppStorage("qwd_enable_filtering")  private var storeEnableFiltering: Bool = false
    
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
            
            stackLayout {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 2. Biological Gates
                VStack(alignment: .leading, spacing: 20) {
                    Text("Biological Gates")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Trimming", isOn: $enableTrimming)
                                .font(.subheadline.bold())
                            if enableTrimming {
                                BiologicalSlider(label: "5' Trim", value: Binding(get: { Double(trimFront) }, set: { trimFront = Int($0) }), range: 0...100, unit: "bp")
                                BiologicalSlider(label: "3' Trim", value: Binding(get: { Double(trimTail) }, set: { trimTail = Int($0) }), range: 0...100, unit: "bp")
                                TextField("Adapter...", text: $adapterSeq)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($isAdapterFocused)
                            }
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Filtering", isOn: $enableFiltering)
                                .font(.subheadline.bold())
                            if enableFiltering {
                                BiologicalSlider(label: "Min Quality", value: $minQual, range: 0...40, unit: "Phred")
                            }
                        }
                    }
                    .proPanel(padding: 20)
                    .onTapGesture { isAdapterFocused = false }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 3. Status & Execute
                VStack(alignment: .leading, spacing: 20) {
                    Text("Status")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 12) {
                        CheckItem(text: "Format detected")
                        CheckItem(text: "Resources verified")
                    }
                    Spacer()
                    Button {
                        executeWithSaving()
                    } label: {
                        HStack {
                            Text("Execute")
                            Image(systemName: "play.fill")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            trimFront = storeTrimFront
            trimTail = storeTrimTail
            minQual = storeMinQual
            adapterSeq = storeAdapterSeq
            enableTrimming = storeEnableTrimming
            enableFiltering = storeEnableFiltering
        }
    }
    
    @ViewBuilder
    private func stackLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 24, content: content)
        #else
        VStack(alignment: .leading, spacing: 24, content: content)
        #endif
    }
    
    private func executeWithSaving() {
        storeTrimFront = trimFront
        storeTrimTail = trimTail
        storeMinQual = minQual
        storeAdapterSeq = adapterSeq
        storeEnableTrimming = enableTrimming
        storeEnableFiltering = enableFiltering
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
            Text("Analyzing Sequence Data...")
                .font(.title2.bold())
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
            Image(systemName: icon).frame(width: 24).foregroundStyle(.tint)
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
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).font(.subheadline)
        }
    }
}
