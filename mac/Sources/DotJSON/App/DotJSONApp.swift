import SwiftUI
import AppKit

@main
struct DotJSONApp: App {
    @State private var workspace = WorkspaceViewModel()

    init() {
        // CLI 模式：参数包含 --cli 时，不走 GUI。
        if CommandLine.arguments.contains("--cli") {
            CLIEntry.main()
        }

        NSApplication.shared.setActivationPolicy(.regular)
        setAppIcon()
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                ContentView()
                ErrorOverlay()
            }
            .environment(workspace)
            .background(WindowConfigurator())
            .preferredColorScheme(.dark)
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 760)
        .commands {
            DotJSONCommands()
        }
        .onChange(of: NSApplication.shared.keyWindow?.isKeyWindow ?? false) { _, isKey in
            if !isKey {
                workspace.persistSession()
            }
        }
    }

    private func setAppIcon() {
        let appIconURL =
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        if let url = appIconURL,
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

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowConfigurationView {
        WindowConfigurationView()
    }

    func updateNSView(_ nsView: WindowConfigurationView, context: Context) {
        nsView.configureCurrentWindow()
    }
}

private final class WindowConfigurationView: NSView {
    private weak var configuredWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureCurrentWindow()
    }

    func configureCurrentWindow() {
        guard let window, configuredWindow !== window else { return }
        configuredWindow = window
        configureWindow(window)
    }

    private func configureWindow(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor(hex: "#1e1e1e")
    }
}
