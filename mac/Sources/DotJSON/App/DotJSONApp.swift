import SwiftUI
import AppKit

@main
struct DotJSONApp: App {
    @State private var viewModel = EditorViewModel()

    init() {
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
            .background(WindowConfigurator())
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 760)
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

/// 将 SwiftUI 场景绑定到真实 `NSWindow`，并持续修正标题栏外观。
///
/// 仅在 `onAppear` 中扫描 `NSApplication.shared.windows` 不可靠：窗口 resize 后系统可能重建
/// 标题栏材质，让深色内容背景透到工具栏区域。这个适配器拿到当前 view 所属窗口，并在 resize
/// 通知后重新施加不透明标题栏与系统窗口背景色。
private struct WindowConfigurator: NSViewRepresentable {
    /// 创建一个不参与布局的占位 AppKit 视图。
    ///
    /// - Parameter context: SwiftUI 提供的上下文。
    /// - Returns: 零尺寸配置视图。
    func makeNSView(context: Context) -> WindowConfigurationView {
        WindowConfigurationView()
    }

    /// SwiftUI 更新时重新检查当前窗口。
    ///
    /// - Parameters:
    ///   - nsView: 当前占位配置视图。
    ///   - context: SwiftUI 提供的上下文。
    func updateNSView(_ nsView: WindowConfigurationView, context: Context) {
        nsView.configureCurrentWindow()
    }
}

/// 挂在 SwiftUI 层级中的窗口配置视图。
private final class WindowConfigurationView: NSView {
    private weak var configuredWindow: NSWindow?

    /// 视图进入窗口后立即配置，并注册 resize 后的重复配置。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureCurrentWindow()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 配置当前所属窗口，并在窗口变化时更新通知监听目标。
    func configureCurrentWindow() {
        guard let window else { return }
        configureWindow(window)
        guard configuredWindow !== window else { return }

        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: configuredWindow)
        configuredWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window,
        )
    }

    /// 窗口 resize 后重新施加标题栏背景，抵消系统重建标题栏材质带来的透明状态。
    ///
    /// - Parameter notification: `NSWindow.didResizeNotification`，其 object 是当前窗口。
    @objc private func handleWindowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        configureWindow(window)
    }

    /// 对窗口施加稳定的标题栏背景配置。
    ///
    /// - Parameter window: 当前 SwiftUI 场景对应的真实 `NSWindow`。
    private func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor
    }
}
