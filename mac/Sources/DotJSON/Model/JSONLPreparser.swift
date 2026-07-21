import Foundation
import DotJSONCore

/// Lightweight JSONL (JSON Lines) preparser.
/// Splits a JSONL file into individual lines without parsing each,
/// and can parse individual lines into `JSONNode` on demand.
///
/// V2 scope — API contract in place, full implementation TBD.
struct JSONLPreparser: Sendable {

    struct LineInfo: Sendable, Equatable {
        let index: Int
        let rawText: String
        let byteOffset: Int
        var isValid: Bool
    }

    let lines: [LineInfo]

    /// 按物理行预解析 JSONL 文本，并跳过不承载记录的纯空白行。
    ///
    /// - Parameter rawContent: 原始 JSONL 文本；每个非空白物理行视为一条候选记录。
    init(rawContent: String) {
        var result = [LineInfo]()
        var offset = 0
        let rawLines = rawContent.components(separatedBy: .newlines)
        for (i, line) in rawLines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // 空白行不是 JSONL 记录，但仍计入字节偏移，保证后续错误定位指向原文。
                offset += line.utf8.count + 1
                continue
            }
            let isValid = (try? JSONParser.parse(line)) != nil
            result.append(LineInfo(
                index: i,
                rawText: line,
                byteOffset: offset,
                isValid: isValid
            ))
            offset += line.utf8.count + 1
        }
        self.lines = result
    }

    /// 有效候选记录的数量。
    var count: Int { lines.count }

    /// 按预解析后的记录索引解析单行 JSON。
    ///
    /// - Parameter index: `lines` 数组中的记录索引，而非原始物理行号。
    /// - Returns: 解析成功时返回 JSON 节点；索引越界或该行无效时返回 `nil`。
    func parseLine(at index: Int) -> JSONNode? {
        guard lines.indices.contains(index) else { return nil }
        return try? JSONParser.parse(lines[index].rawText)
    }
}
