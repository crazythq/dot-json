import Foundation
import Testing
@testable import DotJSON

/// 验证真实文件替换不会丢失源文件权限。
struct AtomicFileWriterTests {
    @Test func replacesContentAndPreservesMode() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("input.json")
        try Data("{'ok': True}".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)

        try AtomicFileWriter.write("{\"ok\": true}", to: file.path, preservingModeFrom: file.path)

        #expect(try String(contentsOf: file, encoding: .utf8) == "{\"ok\": true}")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect(attributes[.posixPermissions] as? Int == 0o640)
    }
}
