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
    }

    /// 设置 Dock 和应用切换器使用的图标。
    ///
    /// 打包脚本会把图标复制到主 Bundle，因此优先直接读取主 Bundle；仅在 `swift run`
    /// 等未打包场景下回退到 SwiftPM 资源 Bundle，避免启动期无谓遍历资源目录。
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

/// 将 SwiftUI 场景绑定到真实 `NSWindow`，并固定窗口的深色外观。
///
/// 仅在 `onAppear` 中扫描 `NSApplication.shared.windows` 不可靠，因此通过占位 AppKit 视图
/// 获取它实际所属的窗口。外观只在绑定新窗口时配置一次，避免 resize 期间动态修改标题栏后，
/// 已创建的 SwiftUI 工具栏仍保留旧配色而出现黑底黑字。
private struct WindowConfigurator: NSViewRepresentable {
    /// 创建一个不参与布局的占位 AppKit 视图。
    ///
    /// - Parameter context: SwiftUI 提供的上下文。
    /// - Returns: 零尺寸配置视图。
    func makeNSView(context: Context) -> WindowConfigurationView {
        WindowConfigurationView()
    }

    /// SwiftUI 更新时检查占位视图是否被移动到了另一扇窗口。
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

    /// 视图进入窗口后立即配置该窗口。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureCurrentWindow()
    }

    /// 配置当前所属窗口；同一窗口只配置一次。
    func configureCurrentWindow() {
        guard let window, configuredWindow !== window else { return }
        configuredWindow = window
        configureWindow(window)
    }

    /// 对窗口施加稳定的标题栏背景配置。
    ///
    /// - Parameter window: 当前 SwiftUI 场景对应的真实 `NSWindow`。
    private func configureWindow(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor(hex: "#1e1e1e")
    }
}
