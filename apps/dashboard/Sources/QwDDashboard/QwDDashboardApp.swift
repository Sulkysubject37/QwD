import SwiftUI
import UniformTypeIdentifiers

@main
struct QwDDashboardApp: App {
    @State private var engine = QwDEngine.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .frame(minWidth: 1000, minHeight: 700)
                .onReceive(NotificationCenter.default.publisher(for: .qwdOpenFile)) { notif in
                    if let path = notif.object as? String {
                        Task { await engine.runQC(on: path) }
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Sequence File…") {
                    let panel = NSOpenPanel()
                    panel.message = "Choose a FASTQ or BAM file to analyze"
                    panel.begin { resp in
                        if resp == .OK, let url = panel.url {
                            Task { await engine.runQC(on: url.path) }
                        }
                    }
                }
                .keyboardShortcut("o")
            }
        }
    }
}

// ─────────────────────────────────────────────
// Content View — Clean Sidebar & Detail
// ─────────────────────────────────────────────

struct ContentView: View {
    @Environment(QwDEngine.self) private var engine
    @State private var selectedPage: Page? = .dashboard

    enum Page: Hashable, CaseIterable {
        case dashboard, fastqQC, settings

        var label: String {
            switch self {
            case .dashboard: "Dashboard"
            case .fastqQC:   "Sequence Archive"
            case .settings:  "Settings"
            }
        }
        var icon: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .fastqQC:   "tray.full"
            case .settings:  "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, id: \.self, selection: $selectedPage) { page in
                NavigationLink(value: page) {
                    Label(page.label, systemImage: page.icon)
                }
            }
            .navigationTitle("QwD Dashboard")
        } detail: {
            ZStack {
                GlassBackground()
                
                Group {
                    switch selectedPage {
                    case .dashboard:  DashboardView()
                    case .fastqQC:    ArchivePlaceholder()
                    case .settings:   SettingsView()
                    case nil:         DashboardView()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let panel = NSOpenPanel()
                    panel.begin { resp in
                        if resp == .OK, let url = panel.url {
                            Task { await engine.runQC(on: url.path) }
                        }
                    }
                } label: {
                    Label("Add File", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    engine.lastReport = nil
                } label: {
                    Label("Clear Result", systemImage: "trash")
                }
                .disabled(engine.lastReport == nil)
            }
        }
    }
}

struct ArchivePlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.full")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sequence Archive")
                .font(.title2.bold())
            Text("Past analysis reports will be listed here.")
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
