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
}
