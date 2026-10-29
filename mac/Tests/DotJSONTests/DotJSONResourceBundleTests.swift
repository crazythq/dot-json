import Foundation
import Testing
@testable import DotJSON

/// 资源包解析与源码约束的回归测试。
struct DotJSONResourceBundleTests {
    /// 打包后的 `.app` 应能从主 bundle 的 Resources 找到 SwiftPM 资源包。
    @Test func resourceBundleResolvesForPackagedAppLayout() {
        let bundle = DotJSONResourceBundle.bundle
        #expect(bundle != Bundle.main || Bundle.main.url(forResource: "DotJSON_DotJSON", withExtension: "bundle") != nil)
        let localized = bundle.localizedString(forKey: "toolbar.convert", value: nil, table: nil)
        #expect(!localized.isEmpty)
        #expect(localized != "toolbar.convert")
    }

    /// `mac/` 包根目录（本文件位于 `Tests/DotJSONTests/`）。
    private func macPackageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// 应用源码不得再直接引用会在 `.app` 启动时 fatal 的 `Bundle.module`。
    @Test func appSourcesDoNotReferenceSwiftPackageBundleModule() throws {
        let sourcesRoot = macPackageRoot().appendingPathComponent("Sources/DotJSON")

        let swiftFiles = try FileManager.default.subpathsOfDirectory(atPath: sourcesRoot.path)
            .filter { $0.hasSuffix(".swift") }

        for relativePath in swiftFiles {
            let url = sourcesRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            let withoutComments = source
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
                .joined(separator: "\n")
            #expect(!withoutComments.contains("Bundle.module"), "unexpected Bundle.module in \(relativePath)")
            #expect(!withoutComments.contains("bundle: .module"), "unexpected bundle: .module in \(relativePath)")
        }
    }
}
