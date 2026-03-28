import SwiftUI

struct DashboardView: View {
    @Environment(QwDEngine.self) private var engine
    @State private var isTargeted = false

    var body: some View {
        VStack {
            if engine.isRunning {
                AnalyzingView()
            } else if let report = engine.lastReport {
                ReportView(report: report)
            } else {
                DropZoneView(isTargeted: $isTargeted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassBackground())
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await engine.runQC(on: url.path) }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}

// ─────────────────────────────────────────────
// Native Drop Zone
// ─────────────────────────────────────────────

struct DropZoneView: View {
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            
            VStack(spacing: 8) {
                Text("Select a Sequence File")
                    .font(.title2.bold())
                
                Text("Drop FASTQ or BAM files here to start QC analysis.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Choose File…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = []
                panel.begin { resp in
                    if resp == .OK, let url = panel.url {
                        NotificationCenter.default.post(name: .qwdOpenFile, object: url.path)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(width: 440, height: 320)
        .proPanel(padding: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : .secondary.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [8, 4]))
        }
        .shadow(color: .black.opacity(0.02), radius: 10, y: 5)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
    }
}

// ─────────────────────────────────────────────
// Analyzing View
// ─────────────────────────────────────────────

struct AnalyzingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            
            Text("Analyzing Sequences…")
                .font(.headline)
            
            Text("Performing high-quality sequence assessment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(width: 440, height: 320)
        .proPanel(padding: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.secondary.opacity(0.05), lineWidth: 1)
        }
    }
}

extension Notification.Name {
    static let qwdOpenFile = Notification.Name("qwdOpenFile")
}
