import Foundation
import Testing
@testable import DotJSON

/// 应用窗口配置的结构性回归测试。
struct DotJSONAppTests {
    /// 读取真实 App 入口源码。
    ///
    /// - Returns: `DotJSONApp.swift` 的完整源码文本。
    /// - Throws: 无法读取 App 源码时抛出文件读取错误。
    private func appSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/App/DotJSONApp.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    /// 验证应用只设置默认窗口尺寸，不限制用户可缩放的最小宽高。
    ///
    /// - Throws: 无法读取 App 源码时抛出文件读取错误。
    @Test func appSetsDefaultWindowSizeWithoutMinimumSizeConstraints() throws {
        let source = try appSource()

        #expect(source.contains(".defaultSize(width: 900, height: 760)"))
        #expect(!source.contains(".frame(minWidth:"))
        #expect(!source.contains("minHeight:"))
        #expect(!source.contains(".windowResizability(.contentMinSize)"))
    }

    /// 验证窗口外观只在绑定窗口时固定为深色，不在 resize 时重复改写动态颜色。
    ///
    /// - Throws: 无法读取 App 源码时抛出文件读取错误。
    @Test func appConfiguresStableDarkWindowAppearanceWithoutResizeObserver() throws {
        let source = try appSource()

        #expect(source.contains(".background(WindowConfigurator())"))
        #expect(source.contains("private struct WindowConfigurator: NSViewRepresentable"))
        #expect(source.contains("configureWindow(window)"))
        #expect(source.contains("window.appearance = NSAppearance(named: .darkAqua)"))
        #expect(source.contains("window.titlebarAppearsTransparent = false"))
        #expect(source.contains("window.backgroundColor = NSColor(hex: \"#1e1e1e\")"))
        #expect(!source.contains("NSWindow.didResizeNotification"))
        #expect(!source.contains("for window in NSApplication.shared.windows"))
    }

    /// 验证打包应用优先从主 Bundle 读取已经复制到 Resources 的图标。
    ///
    /// SwiftPM 的 `Bundle.module` 会在启动期重新遍历资源 Bundle；打包后的主 Bundle
    /// 已经包含图标，直接读取可以避免文件系统异常时阻塞整个应用初始化。
    @Test func packagedAppLoadsIconFromMainBundleBeforeSwiftPackageBundle() throws {
        let source = try appSource()

        let mainBundleLookup = try #require(source.range(of: "Bundle.main.url(forResource:"))
        let moduleBundleLookup = try #require(source.range(of: "Bundle.module.url(forResource:"))
        #expect(mainBundleLookup.lowerBound < moduleBundleLookup.lowerBound)
    }
}
