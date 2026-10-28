import Foundation

/// 在 SwiftPM 直出二进制与 `.app` 包两种布局下定位 `DotJSON` 目标的处理后资源包。
///
/// SwiftPM 生成的 `Bundle.module` 会在可执行文件旁查找 `DotJSON_DotJSON.bundle`；
/// `build-app.sh` 把该 bundle 放进 `Contents/Resources/`，因此必须显式从主 bundle 的 Resources 解析。
enum DotJSONResourceBundle {
    private static let bundleBaseName = "DotJSON_DotJSON"

    static let bundle: Bundle = locate()

    private static func locate() -> Bundle {
        if let url = Bundle.main.url(forResource: bundleBaseName, withExtension: "bundle"),
           let resolved = Bundle(url: url) {
            return resolved
        }

        let anchorBundle = Bundle(for: BundleAnchor.self)
        let candidates: [URL] = [
            anchorBundle.url(forResource: bundleBaseName, withExtension: "bundle"),
            anchorBundle.resourceURL?.appendingPathComponent("\(bundleBaseName).bundle"),
            anchorBundle.bundleURL.appendingPathComponent("\(bundleBaseName).bundle"),
            anchorBundle.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("\(bundleBaseName).bundle"),
            anchorBundle.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(bundleBaseName).bundle"),
        ].compactMap { $0 }

        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path),
                  let resolved = Bundle(url: url) else {
                continue
            }
            return resolved
        }

        return anchorBundle
    }
}

private final class BundleAnchor: NSObject {}
