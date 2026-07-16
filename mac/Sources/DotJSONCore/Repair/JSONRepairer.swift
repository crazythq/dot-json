import Foundation

/// 对常见 AI/Python JSON 文本执行确定性、保守修复。
public enum JSONRepairer {
    /// 修复过程中可被 CLI 稳定映射的错误。
    public struct RepairError: Error, LocalizedError, Sendable, Equatable {
        /// 错误分类；调用方不应依赖自然语言文案判断类型。
        public enum Kind: String, Sendable {
            case ambiguousCandidate
            case unsupportedSyntax
            case invalidResult
        }

        public let kind: Kind
        public let message: String
        public let byteOffset: Int?

        /// 面向用户的错误说明。
        public var errorDescription: String? { message }

        /// 创建结构化修复错误。
        ///
        /// - Parameters:
        ///   - kind: 稳定错误分类。
        ///   - message: 面向用户的错误说明。
        ///   - byteOffset: 原输入中的 UTF-8 字节偏移；无法定位时为 `nil`。
        public init(kind: Kind, message: String, byteOffset: Int? = nil) {
            self.kind = kind
            self.message = message
            self.byteOffset = byteOffset
        }
    }

    /// 把可确定修复的输入转换为标准 JSON，同时保留原排版。
    ///
    /// - Parameter input: 标准 JSON、Python `dict/list` 文本或单块 AI 包装文本。
    /// - Returns: 只完成必要语法修复的 JSON；合法输入原样返回。
    /// - Throws: 输入含多个候选、使用不支持语法或修复后仍无效时抛出 `RepairError`。
    public static func repair(_ input: String) throws(RepairError) -> String {
        // 合法 JSON 必须走零修改快路径，避免 repair 意外承担格式化职责。
        if (try? JSONFormatter.validate(input)) != nil {
            return input
        }

        let candidate = try JSONCandidateExtractor.extractUnique(from: input)
        let repaired = try PythonLiteralRepairer.repair(candidate.text)
        guard (try? JSONFormatter.validate(repaired)) != nil else {
            throw RepairError(
                kind: .invalidResult,
                message: "Input cannot be repaired without guessing.",
                byteOffset: candidate.originalUTF8Offset
            )
        }
        return repaired
    }
}
