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

    init(rawContent: String) {
        var result = [LineInfo]()
        var offset = 0
        let rawLines = rawContent.components(separatedBy: .newlines)
        for (i, line) in rawLines.enumerated() {
            if i == rawLines.count - 1 && line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
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

    var count: Int { lines.count }

    func parseLine(at index: Int) -> JSONNode? {
        guard lines.indices.contains(index) else { return nil }
        return try? JSONParser.parse(lines[index].rawText)
    }
}
