import SwiftUI
import Charts

// ─────────────────────────────────────────────
// QwD Dashboard — High-Fidelity Scientific Report
// ─────────────────────────────────────────────

struct ReportView: View {
    let report: QCReport
    @State private var showingInspector = false

    var body: some View {
        ScrollView {
            ReportBodyView(report: report, showingInspector: $showingInspector)
        }
        .background(GlassBackground())
        .sheet(isPresented: $showingInspector) {
            InspectorSidebar(report: report)
        }
    }
}

// ─────────────────────────────────────────────
// UI View (For the Dashboard)
// ─────────────────────────────────────────────

struct ReportBodyView: View {
    let report: QCReport
    @Binding var showingInspector: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            HeaderBar(report: report, showingInspector: $showingInspector)
            MetricSummaryGrid(report: report)
            
            if let alignment = report.stages.alignment_stats {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(text: "BAM Alignment Statistics")
                    HStack(spacing: 20) {
                        SummaryTile(label: "Mapped Reads", value: alignment.mapped_reads.compactFormatted, unit: "Reads", trend: .nominal)
                        SummaryTile(label: "Mean MAPQ", value: String(format: "%.1f", alignment.mean_mapq), unit: "Quality", trend: .neutral)
                        if let cov = report.stages.coverage {
                            SummaryTile(label: "Est. Coverage", value: String(format: "%.2f", cov.coverage_estimate), unit: "x", trend: .nominal)
                        }
                    }
                }
            }
            
            HStack(alignment: .top, spacing: 20) {
                DistributionPanel(title: "GC Composition", icon: "leaf.fill") {
                    if let gc = report.stages.gc_distribution {
                        GCChart(bins: gc.bins, isPrinting: false)
                    }
                }
                DistributionPanel(title: "Length Profile", icon: "chart.bar.fill") {
                    if let len = report.stages.length_distribution {
                        LengthChart(bins: len.bins, isPrinting: false)
                    }
                }
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    if let dup = report.stages.duplication {
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
                .frame(width: 300)
                
                if let over = report.stages.overrepresented {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Anomalous Sequence Patterns")
                        OverrepresentedTable(stats: over)
                            .proPanel(padding: 0)
                    }
                }
            }
            Spacer(minLength: 40)
        }
        .padding(32)
    }
}

// ─────────────────────────────────────────────
// Scientific Print View (Optimized for A4/Vector PDF)
// ─────────────────────────────────────────────

struct ScientificPrintView: View {
    let report: QCReport
    let timestamp = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Formal Provenance Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SEQUENCE QUALITY ASSESSMENT REPORT")
                        .font(.system(size: 18, weight: .black))
                    Text("QwD Scientific Core — Deterministic Trace Output")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("REPORT_ID: \(timestamp.timeIntervalSince1970.description.prefix(10))")
                    Text("TIMESTAMP: \(timestamp.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.gray)
            }
            
            Divider().padding(.vertical, 8)

            // Primary Telemetry
            HStack(spacing: 40) {
                PrintMetric(label: "TOTAL READS", value: report.read_count.formatted())
                if let bs = report.stages.basic_stats {
                    PrintMetric(label: "TOTAL BASES", value: bs.total_bases.formatted())
                    PrintMetric(label: "MEAN LENGTH", value: String(format: "%.1f bp", bs.mean_length))
                }
                if let n50 = report.stages.n_statistics?.n50 {
                    PrintMetric(label: "N50 METRIC", value: "\(n50) bp")
                }
            }

            // Visual Analytics (Vector Optimized)
            VStack(alignment: .leading, spacing: 32) {
                PrintDistributionSection(title: "GC Composition Profile", icon: "leaf") {
                    if let gc = report.stages.gc_distribution {
                        GCChart(bins: gc.bins, isPrinting: true)
                    }
                }
                
                PrintDistributionSection(title: "Read Length Distribution", icon: "ruler") {
                    if let len = report.stages.length_distribution {
                        LengthChart(bins: len.bins, isPrinting: true)
                    }
                }
            }

            // Bottom Summary
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 12) {
                GridRow {
                    Text("METRIC").font(.system(size: 8, weight: .bold))
                    Text("VALUE").font(.system(size: 8, weight: .bold))
                    Text("STATUS").font(.system(size: 8, weight: .bold))
                }
                if let dup = report.stages.duplication {
                    GridRow {
                        Text("Sequence Duplication").font(.system(size: 10))
                        Text(String(format: "%.2f%%", dup.duplication_ratio * 100))
                        Text(dup.duplication_ratio > 0.2 ? "WARNING" : "NOMINAL")
                            .foregroundStyle(dup.duplication_ratio > 0.2 ? Color.orange : Color.green)
                    }
                }
            }
            .padding()
            .border(Color.gray.opacity(0.2))

            Spacer()
            
            // Professional Footer
            HStack {
                Text("QwD Core Engine v\(report.version)")
                Spacer()
                Text("Native ARM64/NEON Vectorized Pipeline")
            }
            .font(.system(size: 7, design: .monospaced))
            .foregroundStyle(.gray)
        }
        .padding(40)
        .frame(width: 595, height: 842) // A4 at 72 DPI (Points)
        .background(Color.white)
    }
}

// MARK: - Component Helpers

struct HeaderBar: View {
    let report: QCReport
    @Binding var showingInspector: Bool
    
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quality Control Report")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Engine v\(report.version) • \(report.read_count.formatted()) Sequences")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                Button(action: { showingInspector = true }) {
                    Label("Inspect", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                
                Button(action: exportPDF) {
                    Label("Export PDF", systemImage: "printer.filled")
                }
                .buttonStyle(.bordered)

                Button(action: exportJSON) {
                    Label("Save JSON", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    @MainActor
    private func exportPDF() {
        let printView = ScientificPrintView(report: report)
        let renderer = ImageRenderer(content: printView)
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "qwd_report_\(report.version).pdf"
        
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                renderer.render { size, context in
                    var box = CGRect(origin: .zero, size: size)
                    guard let pdfContext = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                    
                    pdfContext.beginPDFPage(nil)
                    context(pdfContext) // This draws vector data from SwiftUI to PDF
                    pdfContext.endPDFPage()
                    pdfContext.closePDF()
                }
            }
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                let data = try? JSONEncoder().encode(report)
                try? data?.write(to: url)
            }
        }
    }
}

struct PrintMetric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(.gray)
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded))
        }
    }
}

struct PrintDistributionSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 10, weight: .bold))
            }
            content().frame(height: 120)
        }
    }
}

// ─────────────────────────────────────────────
// Optimized Vector Charts
// ─────────────────────────────────────────────

struct GCChart: View {
    let bins: [Int]
    let isPrinting: Bool
    var body: some View {
        Chart {
            ForEach(Array(bins.enumerated()), id: \.offset) { i, c in
                AreaMark(x: .value("%", i * 10), y: .value("R", c))
                    .foregroundStyle(isPrinting ? Color.black.opacity(0.05).gradient : QwDPalette.accent.opacity(0.1).gradient)
                LineMark(x: .value("%", i * 10), y: .value("R", c))
                    .foregroundStyle(isPrinting ? Color.black : QwDPalette.accent)
                    .lineStyle(StrokeStyle(lineWidth: isPrinting ? 1 : 2))
            }
        }
        .chartXAxis { AxisMarks(values: [0, 50, 100]) }
        .chartYAxis(.hidden)
    }
}

struct LengthChart: View {
    let bins: [Int]
    let isPrinting: Bool
    let labels = ["<100", "500", "1k", "5k", "10k", "10k+"]
    var body: some View {
        Chart {
            ForEach(Array(zip(labels, bins).enumerated()), id: \.offset) { _, pair in
                BarMark(x: .value("L", pair.0), y: .value("R", pair.1))
                    .foregroundStyle(isPrinting ? Color.black.opacity(0.8).gradient : Color.blue.gradient)
            }
        }
        .chartYAxis(.hidden)
    }
}

// ─────────────────────────────────────────────
// Internal UI Components
// ─────────────────────────────────────────────

struct MetricSummaryGrid: View {
    let report: QCReport
    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                if let stats = report.stages.basic_stats {
                    SummaryTile(label: "Throughput", value: stats.total_bases.compactFormatted, unit: "Bases", trend: .nominal)
                    SummaryTile(label: "Avg. Length", value: String(format: "%.0f", stats.mean_length), unit: "bp", trend: .neutral)
                } else if let alignment = report.stages.alignment_stats {
                    SummaryTile(label: "Total Records", value: alignment.total_records.compactFormatted, unit: "Reads", trend: .neutral)
                }
                
                if let n50 = report.stages.n_statistics?.n50 {
                    SummaryTile(label: "N50 Metric", value: "\(n50)", unit: "bp", trend: .nominal)
                }
                
                if report.stages.gc_distribution != nil {
                    SummaryTile(label: "GC Content", value: String(format: "%.1f", calculateGC(report)), unit: "%", trend: .neutral)
                }
            }
        }
    }
    private func calculateGC(_ r: QCReport) -> Double {
        guard let bins = r.stages.gc_distribution?.bins else { return 0 }
        let total = bins.reduce(0, +)
        if total == 0 { return 0 }
        var sum: Double = 0
        for (i, count) in bins.enumerated() { sum += Double(i * 10) * Double(count) }
        return sum / Double(total)
    }
}

struct SummaryTile: View {
    let label: String; let value: String; let unit: String; let trend: BioTrend
    enum BioTrend { case nominal, neutral, warning, critical }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(.system(size: 10, weight: .black)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(unit).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Circle().fill(trendColor.gradient).frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).proPanel()
    }
    var trendColor: Color {
        switch trend {
        case .nominal: QwDPalette.bioNominal; case .neutral: QwDPalette.bioNeutral
        case .warning: QwDPalette.bioWarning; case .critical: QwDPalette.bioCritical
        }
    }
}

struct DistributionPanel<Content: View>: View {
    let title: String; let icon: String; @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.subheadline.bold()).foregroundStyle(.secondary)
            content().frame(height: 180)
        }
        .frame(maxWidth: .infinity).proPanel()
    }
}

struct IntegrityTile<Content: View>: View {
    let title: String; let icon: String; @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).proPanel()
    }
}

struct OverrepresentedTable: View {
    let stats: OverrepresentedStats
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Detected Sequence"); Spacer(); Text("Frequency") }
            .font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8).background(Color.primary.opacity(0.03))
            HStack(alignment: .top) {
                Text(stats.most_frequent).font(.system(.body, design: .monospaced)).foregroundStyle(QwDPalette.accent)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(stats.most_frequent_count.formatted())").font(.headline.bold())
                    Text("Occurrences").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }.padding(16)
            Divider()
            HStack { Text("Pattern Diversity Index").font(.caption).foregroundStyle(.secondary); Spacer()
                Text("\(stats.unique_sequences.formatted()) unique").font(.caption.bold())
            }.padding(12)
        }
    }
}

struct DuplicationMiniChart: View {
    let stats: DuplicationStats
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle().trim(from: 0, to: stats.duplication_ratio)
                    .stroke(stats.duplication_ratio > 0.2 ? QwDPalette.bioWarning.gradient : QwDPalette.bioNominal.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }.frame(width: 44, height: 44)
            VStack(alignment: .leading) {
                Text(String(format: "%.1f%%", stats.duplication_ratio * 100)).font(.headline.bold())
                Text("Total Duplicates").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}

struct EntropyMiniChart: View {
    let stats: EntropyStats
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "%.4f bits", stats.entropy)).font(.headline.bold())
            GeometryReader { geo in
                Capsule().fill(.quaternary).overlay(alignment: .leading) {
                    Capsule().fill(Color.purple.gradient).frame(width: geo.size.width * min(stats.entropy / 2.0, 1.0))
                }
            }.frame(height: 6)
        }
    }
}

struct InspectorSidebar: View {
    let report: QCReport; @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Engine Profile") { LabeledContent("QwD Version", value: report.version); LabeledContent("Target Platform", value: "Native ARM64/SIMD") }
                Section("Raw Telemetry") { LabeledContent("Read Count", value: "\(report.read_count)")
                    if let bs = report.stages.basic_stats {
                        LabeledContent("Bases Processed", value: "\(bs.total_bases)")
                        LabeledContent("Shortest Read", value: "\(bs.min_length) bp"); LabeledContent("Longest Read", value: "\(bs.max_length) bp")
                    }
                }
            }
            .navigationTitle("Telemetry Details").toolbar { Button("Done") { dismiss() } }
        }.frame(width: 350, height: 500)
    }
}

struct SectionLabel: View {
    let text: String; var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .black)).foregroundStyle(.tertiary) }
}

extension Int {
    var compactFormatted: String {
        if self >= 1_000_000_000 { return String(format: "%.1fB", Double(self)/1e9) }
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self)/1e6) }
        if self >= 1_000 { return String(format: "%.1fK", Double(self)/1e3) }
        return "\(self)"
    }
}
