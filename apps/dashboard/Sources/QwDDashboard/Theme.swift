import SwiftUI
#if os(macOS)
import AppKit
#endif

// ─────────────────────────────────────────────
// QwD Design System — "Lab Professional"
// ─────────────────────────────────────────────

enum QwDPalette {
    // Core Brand
    static let accent = Color.accentColor
    
    // Status Semantic Colors (Researcher-Focused)
    static let bioNominal  = Color.green
    static let bioWarning  = Color.orange
    static let bioCritical = Color.red
    static let bioNeutral  = Color.blue
    
    // Grays for Hierarchy
    static let secondaryLabel = Color.secondary.opacity(0.8)
    static let separator      = Color.primary.opacity(0.06)
    
    // Backgrounds
    #if os(macOS)
    static let windowBackground = Color(nsColor: NSColor.windowBackgroundColor)
    #else
    static let windowBackground = Color(uiColor: .systemBackground)
    #endif
    static let panelBackground  = Color.white.opacity(0.5) // For Light Mode
    static let panelBackgroundDark = Color.black.opacity(0.2) // For Dark Mode
    
    // Print Optimized
    static let printText = Color.black
    static let printSecondary = Color.gray
    static let printBorder = Color.black.opacity(0.1)
}

// MARK: - Professional Glass Panel
struct ProMetricPanel: ViewModifier {
    var padding: CGFloat = 16
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(QwDPalette.separator, lineWidth: 1)
                    .allowsHitTesting(false) // CRITICAL: Prevent overlay from blocking TextField input
            }
    }
}

extension View {
    func proPanel(padding: CGFloat = 16) -> some View {
        modifier(ProMetricPanel(padding: padding))
    }
}

// MARK: - Subtle Lab Background
struct GlassBackground: View {
    var body: some View {
        ZStack {
            QwDPalette.windowBackground
                .ignoresSafeArea()
            
            // Subtle, non-distracting gradient to break the flatness
            LinearGradient(
                colors: [Color.accentColor.opacity(0.03), Color.blue.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

