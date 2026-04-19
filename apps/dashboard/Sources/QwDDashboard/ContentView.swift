import SwiftUI

struct ContentView: View {
    @Environment(QwDEngine.self) private var engine
    @State private var selectedTab: Tab = .dashboard

    enum Tab {
        case dashboard
        case settings
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: Tab.dashboard) {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
                .tag(Tab.dashboard)

                NavigationLink(value: Tab.settings) {
                    Label("Global Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
            }
            .navigationTitle("QwD Pro")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            #endif
        } detail: {
            switch selectedTab {
            case .dashboard:
                DashboardView()
            case .settings:
                SettingsView()
            }
        }
    }
}
