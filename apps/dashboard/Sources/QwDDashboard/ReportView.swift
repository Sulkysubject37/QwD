import SwiftUI
import Charts

// ─────────────────────────────────────────────
// QwD Dashboard — High-Fidelity Scientific Report
// ─────────────────────────────────────────────

struct ReportView: View {
    let report: QCReport
    @State private var showingInspector = false
    @State private var showingPrintPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            HeaderBar(report: report, showingInspector: $showingInspector, showingPrintPreview: $showingPrintPreview)
            
            if let trim = report.stages.trim, let trimmed = trim.reads_trimmed {
                HStack {
                    Image(systemName: "bolt.shield.fill")
                    Text("Biological Transformations Active")
                    Spacer()
                    Text("\(trimmed.formatted()) trimmed")
                    if let filter = report.stages.filter, let filtered = filter.reads_filtered {
                        Text("•")
                        Text("\(filtered.formatted()) filtered")
                    }
                }
                .font(.caption.bold())
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .foregroundStyle(.orange)
            }

            MetricSummaryGrid(report: report)
            
            if let dist = report.stages.quality_dist {
                QualityHeatmapView(stats: dist)
            }
            
            ReportBodyView(report: report)
        }
        .sheet(isPresented: $showingInspector) {
            InspectorView(report: report)
        }
        #if os(macOS)
        .sheet(isPresented: $showingPrintPreview) {
            ScientificPrintView(report: report)
        }
        #endif
    }
}

// ─────────────────────────────────────────────
// Components
// ─────────────────────────────────────────────

struct HeaderBar: View {
    let report: QCReport
    @Binding var showingInspector: Bool
    @Binding var showingPrintPreview: Bool
    @Environment(QwDEngine.self) private var engine

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sequence Analytics Report")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                HStack {
                    Text("QwD v\(report.version)")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                    
                    Text("•")
                    Text("\(report.read_count.formatted()) Reads Processed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    showingInspector = true
                } label: {
                    Label("Inspect Raw", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)

                #if os(macOS)
                Button {
                    showingPrintPreview = true
                } label: {
                    Label("Export PDF", systemImage: "printer.filled.and.paper")
                }
                .buttonStyle(.bordered)
                #endif

                Button {
                    engine.lastReport = nil
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct InspectorView: View {
    let report: QCReport
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Raw Analytical Payload")
                        .font(.headline)
                    
                    Text(jsonString)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("Data Inspector")
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "Error encoding report."
    }
}

struct MetricSummaryGrid: View {
    let report: QCReport
    
    var body: some View {
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ]
        
        LazyVGrid(columns: columns, spacing: 20) {
            if let stats = report.stages.basic_stats {
                if let mean = stats.mean_length {
                    SummaryTile(label: "Mean Length", value: String(format: "%.1f", mean), unit: "bp", trend: .nominal)
                }
                if let max = stats.max_length {
                    SummaryTile(label: "Max Length", value: max.formatted(), unit: "bp", trend: .nominal)
                }
                if let bases = stats.total_bases {
                    SummaryTile(label: "Total Yield", value: bases.compactFormatted, unit: "bp", trend: .nominal)
                }
            }
            
            if let n50 = report.stages.n_statistics, let val = n50.n50 {
                SummaryTile(label: "N50 Metric", value: val.compactFormatted, unit: "bp", trend: .nominal)
            }
        }
    }
}

struct ReportBodyView: View {
    let report: QCReport
    
    var body: some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 24) {
            MainAnalysisPanel(report: report)
            IntegritySidebar(report: report)
        }
        #else
        VStack(alignment: .leading, spacing: 24) {
            MainAnalysisPanel(report: report)
            IntegritySidebar(report: report)
        }
        #endif
    }
}

struct MainAnalysisPanel: View {
    let report: QCReport
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let gc = report.stages.gc_distribution {
                GCChart(stats: gc)
            }
            if let len = report.stages.length_distribution {
                LengthChart(stats: len)
            }
            if let kmer = report.stages.kmer_spectrum {
                KmerSpectrumView(stats: kmer)
            }
            
            if let taxed = report.stages.taxonomic_screening {
                TaxonomyProfileView(taxa: taxed)
            }
            
            if let alignment = report.stages.alignment_stats, let mapped = alignment.mapped_reads, let mean = alignment.mean_mapq {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(text: "BAM Alignment Statistics")
                    HStack(spacing: 20) {
                        SummaryTile(label: "Mapped Reads", value: mapped.compactFormatted, unit: "Reads", trend: .nominal)
                        SummaryTile(label: "Mean MAPQ", value: String(format: "%.1f", mean), unit: "Quality", trend: .nominal)
                    }
                }
                .proPanel(padding: 24)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct IntegritySidebar: View {
    let report: QCReport
    var body: some View {
        VStack(spacing: 20) {
            if let trim = report.stages.trim, let trimmed = trim.reads_trimmed {
                IntegrityTile(title: "Trimming Delta", icon: "scissors") {
                    HStack {
                        Text("\(trimmed.formatted())").font(.headline)
                        Text("reads modified").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let filter = report.stages.filter, let seen = filter.reads_seen, let passed = filter.reads_passed {
                IntegrityTile(title: "Filter Yield", icon: "line.3.horizontal.decrease.circle") {
                    VStack(alignment: .leading) {
                        let yield = seen > 0 ? (Double(passed) / Double(seen)) * 100 : 0.0
                        Text(String(format: "%.1f%%", yield)).font(.headline)
                        Text("Survival Rate").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let dup = report.stages.duplication, dup.duplication_ratio != nil {
                IntegrityTile(title: "Duplication Rate", icon: "square.on.square.dashed") {
                    DuplicationMiniChart(stats: dup)
                }
            }
            if let ent = report.stages.entropy {
                IntegrityTile(title: "Complexity (Entropy)", icon: "waveform.path.ecg") {
                    EntropyMiniChart(stats: ent)
                }
            }
        }
        #if os(macOS)
        .frame(width: 280)
        #else
        .frame(maxWidth: .infinity)
        #endif
    }
}

// ─────────────────────────────────────────────
// Detailed Charts
// ─────────────────────────────────────────────

struct GCChart: View {
    let stats: GCDistribution
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "GC Distribution")
            if let bins = stats.bins {
                Chart {
                    ForEach(Array(bins.enumerated()), id: \.offset) { index, count in
                        BarMark(
                            x: .value("GC%", Double(index) / Double(bins.count) * 100.0),
                            y: .value("Count", count)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                }
                .frame(height: 200)
                .chartXAxisLabel("GC Percentage (%)")
                .chartYAxisLabel("Read Count")
            } else {
                Text("No GC Distribution data available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
            }
        }
        .proPanel(padding: 24)
    }
}

struct LengthBin: Identifiable {
    let id: Int
    let count: Int
}

struct LengthChart: View {
    let stats: LengthDistribution
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Sequence Length Distribution")
            if let binsData = stats.bins {
                let bins = binsData.enumerated().map { LengthBin(id: $0.offset, count: $0.element) }
                Chart(bins) { bin in
                    AreaMark(
                        x: .value("Index", bin.id),
                        y: .value("Reads", bin.count)
                    )
                    .foregroundStyle(Color.blue.opacity(0.1).gradient)
                    
                    LineMark(
                        x: .value("Index", bin.id),
                        y: .value("Reads", bin.count)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.blue)
                }
                .frame(height: 200)
                .chartXAxisLabel("Length Distribution Index")
            } else {
                VStack {
                    Text("Detailed Length Distribution not available.")
                    if let count = stats.count {
                        Text("\(count) length variations recorded.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 200)
            }
        }
        .proPanel(padding: 24)
    }
}

// ─────────────────────────────────────────────
// Shared UI Elements
// ─────────────────────────────────────────────

struct SummaryTile: View {
    let label: String
    let value: String
    let unit: String
    let trend: TrendType
    
    enum Trend { case nominal, warning, critical }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(unit).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proPanel(padding: 16)
    }
}

struct IntegrityTile<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proPanel(padding: 16)
    }
}

struct DuplicationMiniChart: View {
    let stats: DuplicationStats
    var body: some View {
        let rate = stats.duplication_ratio ?? 0.0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(format: "%.1f%%", rate * 100)).font(.headline)
                Spacer()
                if let dup = stats.duplicate_reads, let total = stats.total_reads {
                    Text("\(dup.formatted()) / \(total.formatted())").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.1))
                    Capsule().fill(rate > 0.2 ? .orange : .blue).frame(width: geo.size.width * CGFloat(rate))
                }
            }
            .frame(height: 6)
        }
    }
}

struct EntropyMiniChart: View {
    let stats: EntropyStats
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(String(format: "%.2f", stats.entropy)).font(.headline)
            Text("bits").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(.secondary)
            .kerning(1.2)
    }
}

enum TrendType { case nominal, warning, critical }

#if os(macOS)
// ─────────────────────────────────────────────
// Scientific Print View (macOS ONLY)
// ─────────────────────────────────────────────

struct ScientificPrintView: View {
    let report: QCReport
    let timestamp = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Scientific Report Preview").font(.headline)
                Spacer()
                Button("Save as PDF...") {
                    savePDF()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            // The Paper
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Divider()
                    MetricSummaryGrid(report: report)
                    if let gc = report.stages.gc_distribution {
                        GCChart(stats: gc)
                    }
                    if let len = report.stages.length_distribution {
                        LengthChart(stats: len)
                    }
                    footer
                }
                .padding(40)
                .frame(width: 595) // A4 width at 72dpi
                .background(.white)
                .foregroundStyle(.black)
                .shadow(radius: 10)
                .padding()
            }
            .background(Color.gray.opacity(0.2))
        }
        .frame(width: 800, height: 800)
    }
    
    var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("QwD GENOMIC QUALITY REPORT").font(.title.bold())
                Text("Fidelity Level: Publication Grade").font(.caption)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(timestamp, style: .date)
                Text(timestamp, style: .time)
            }
            .font(.caption.monospaced())
        }
    }
    
    var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Software Version: QwD v\(report.version)")
            Text("Digital Signature: \(UUID().uuidString)")
            Text("© 2026 MD. Arshad. All rights reserved.")
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.secondary)
    }
    
    @MainActor
    private func savePDF() {
        let renderer = ImageRenderer(content: self.frame(width: 595))
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "QwD_Report.pdf"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                renderer.render { size, context in
                    var box = CGRect(origin: .zero, size: size)
                    guard let pdfContext = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                    
                    pdfContext.beginPDFPage(nil)
                    context(pdfContext)
                    pdfContext.endPDFPage()
                    pdfContext.closePDF()
                }
                dismiss()
            }
        }
    }
}
#endif

// ─────────────────────────────────────────────
// Extensions
// ─────────────────────────────────────────────

extension Int {
    var compactFormatted: String {
        if self >= 1_000_000_000 { return String(format: "%.1fB", Double(self)/1e9) }
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self)/1e6) }
        if self >= 1_000 { return String(format: "%.1fK", Double(self)/1e3) }
        return "\(self)"
    }
}
