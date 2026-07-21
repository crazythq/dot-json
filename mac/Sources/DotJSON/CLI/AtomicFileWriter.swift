import Foundation

/// 通过同目录临时文件安全替换目标内容。
enum AtomicFileWriter {
    /// 原子写入 UTF-8 文本，可选择继承源文件 POSIX 权限。
    ///
    /// - Parameters:
    ///   - content: 完整输出文本。
    ///   - destinationPath: 目标文件路径。
    ///   - sourcePath: 需要保留权限的源文件；新文件输出传 `nil`。
    /// - Throws: 创建临时文件、设置权限或替换目标失败时抛出文件系统错误。
    static func write(
        _ content: String,
        to destinationPath: String,
        preservingModeFrom sourcePath: String?
    ) throws {
        let manager = FileManager.default
        let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".dotjson-\(UUID().uuidString).tmp")
        var temporaryExists = false

        defer {
            if temporaryExists { try? manager.removeItem(at: temporary) }
        }

        try Data(content.utf8).write(to: temporary, options: .withoutOverwriting)
        temporaryExists = true

        if let sourcePath {
            let attributes = try manager.attributesOfItem(atPath: sourcePath)
            if let mode = attributes[.posixPermissions] {
                try manager.setAttributes([.posixPermissions: mode], ofItemAtPath: temporary.path)
            }
        }

        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: destination)
        }
        temporaryExists = false
    }
}
