import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct QwDDashboardApp: App {
    @State private var engine = QwDEngine.shared

    init() {
        #if os(macOS)
        // CRITICAL: Ensure the app becomes a foreground process with keyboard focus
        NSApplication.shared.setActivationPolicy(.regular)
        
        // Dynamic Branding: Inject the logo into the Dock at runtime
        let logoPath = "../../qwd_logo.png" 
        if let logoImage = NSImage(contentsOfFile: logoPath) ?? NSImage(contentsOfFile: "qwd_logo.png") {
            NSApp.applicationIconImage = logoImage
        }
        
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                #if os(macOS)
                .frame(minWidth: 1000, minHeight: 700)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
        }
        #endif
    }
}
