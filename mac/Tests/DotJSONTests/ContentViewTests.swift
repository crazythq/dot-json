import Foundation
import Testing
@testable import DotJSON

/// 主内容区布局的结构性回归测试。
struct ContentViewTests {
    /// 验证编辑器顶部不再渲染错误文本浮层。
    ///
    /// - Throws: 无法读取主内容区源码时抛出文件读取错误。
    ///
    /// 底部 `ErrorOverlay` 已提供完整错误反馈；顶部浮层会遮挡第一行正文，因此不应存在。
    @Test func contentViewDoesNotRenderTopErrorOverlay() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains(".overlay(alignment: .topTrailing)"))
        #expect(!source.contains("Text(error)"))
    }

    /// 验证右侧搜索框默认隐藏，并由树 Cmd+F 请求显示。
    @Test func treeSearchFieldIsConditionallyShownByTreeFindRequest() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("@State private var treeSearchVisible = false"))
        #expect(source.contains("if treeSearchVisible"))
        #expect(source.contains("TreeView(onRequestFind: showTreeSearch)"))
        #expect(source.contains("onCancel: closeTreeSearch"))
    }

    /// 验证 AppKit 搜索框显式使用可读的深色前景、背景和占位符。
    @Test func treeSearchFieldUsesExplicitDarkThemeColors() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("field.backgroundColor = NSColor(hex: \"#1e1e1e\")"))
        #expect(source.contains("field.textColor = NSColor(hex: \"#d4d4d4\")"))
        #expect(source.contains("field.placeholderAttributedString"))
    }
}
