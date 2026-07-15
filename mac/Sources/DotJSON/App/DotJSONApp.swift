import SwiftUI
import AppKit

@main
struct DotJSONApp: App {
    @State private var viewModel = EditorViewModel()

    init() {
        // Ensure the app appears as a proper macOS app (Dock icon, window switching)
        NSApplication.shared.setActivationPolicy(.regular)
        setAppIcon()
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                ContentView()
                ErrorOverlay()
            }
            .environment(viewModel)
            .frame(minWidth: 900, minHeight: 600)
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            DotJSONCommands()
        }
    }

    private func setAppIcon() {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = img
            return
        }
        let fallback = NSImage(size: NSSize(width: 256, height: 256))
        fallback.lockFocus()
        NSColor(hex: "#1e1e1e").setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 256, height: 256)).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(hex: "#d4d4d4"),
            .font: NSFont.monospacedSystemFont(ofSize: 80, weight: .regular),
        ]
        "{ }".draw(at: NSPoint(x: 40, y: 88), withAttributes: attrs)
        fallback.unlockFocus()
        NSApplication.shared.applicationIconImage = fallback
    }
}
