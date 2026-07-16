import Foundation

/// 从原输入中抽取的唯一对象或数组候选。
struct JSONCandidate: Equatable {
    let text: String
    let originalUTF8Offset: Int
}

/// 识别 Markdown 围栏或说明文字中的唯一完整 JSON 根结构。
enum JSONCandidateExtractor {
    /// 抽取唯一候选；多个或不完整候选会被拒绝。
    ///
    /// - Parameter input: 原始模型/Python 输出。
    /// - Returns: 候选文本及其在原输入中的 UTF-8 偏移。
    /// - Throws: 候选缺失、结构不完整或存在歧义时抛出修复错误。
    static func extractUnique(from input: String) throws(JSONRepairer.RepairError) -> JSONCandidate {
        let bomLength = input.hasPrefix("\u{FEFF}") ? 3 : 0
        let content = input.hasPrefix("\u{FEFF}") ? String(input.dropFirst()) : input

        if content.contains("```") {
            let fenced = try extractFencedCandidates(from: content, baseOffset: bomLength)
            guard fenced.count == 1 else {
                throw JSONRepairer.RepairError(
                    kind: .ambiguousCandidate,
                    message: "Multiple JSON candidates found."
                )
            }
            return fenced[0]
        }

        let balanced = try extractBalancedCandidates(from: content, baseOffset: bomLength)
        guard balanced.count == 1 else {
            throw JSONRepairer.RepairError(
                kind: balanced.isEmpty ? .unsupportedSyntax : .ambiguousCandidate,
                message: balanced.isEmpty
                    ? "No complete JSON object or array found."
                    : "Multiple JSON candidates found."
            )
        }
        if content.trimmingCharacters(in: .whitespacesAndNewlines) == balanced[0].text {
            // 根结构之外只有合法 JSON 空白时保留整段文本，repair 不应吞掉结尾换行。
            return JSONCandidate(text: content, originalUTF8Offset: bomLength)
        }
        return balanced[0]
    }

    /// 解析完整的三反引号围栏，并仅接受空、json、python 标签。
    private static func extractFencedCandidates(
        from input: String,
        baseOffset: Int
    ) throws(JSONRepairer.RepairError) -> [JSONCandidate] {
        var result: [JSONCandidate] = []
        var cursor = input.startIndex

        while let opening = input.range(of: "```", range: cursor..<input.endIndex) {
            guard let headerEnd = input[opening.upperBound...].firstIndex(of: "\n") else {
                throw unsupported("Incomplete Markdown code fence.", input: input, at: opening.lowerBound)
            }
            guard let closing = input.range(of: "```", range: headerEnd..<input.endIndex) else {
                throw unsupported("Incomplete Markdown code fence.", input: input, at: opening.lowerBound)
            }

            let label = input[opening.upperBound..<headerEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard label.isEmpty || label == "json" || label == "python" else {
                throw unsupported("Unsupported Markdown code fence language.", input: input, at: opening.lowerBound)
            }

            let bodyStart = input.index(after: headerEnd)
            let body = String(input[bodyStart..<closing.lowerBound])
            result.append(JSONCandidate(
                text: body,
                originalUTF8Offset: baseOffset + input[..<bodyStart].utf8.count
            ))
            cursor = closing.upperBound
        }
        return result
    }

    /// 以字符串感知的括号栈扫描说明文字中的顶层对象或数组。
    private static func extractBalancedCandidates(
        from input: String,
        baseOffset: Int
    ) throws(JSONRepairer.RepairError) -> [JSONCandidate] {
        var result: [JSONCandidate] = []
        var stack: [Character] = []
        var rootStart: String.Index?
        var quote: Character?
        var escaped = false
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]

            if rootStart != nil, let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                index = input.index(after: index)
                continue
            }

            if rootStart != nil, character == "\"" || character == "'" {
                quote = character
                index = input.index(after: index)
                continue
            }

            if character == "{" || character == "[" {
                if rootStart == nil { rootStart = index }
                stack.append(character)
            } else if character == "}" || character == "]", rootStart != nil {
                guard let opening = stack.last,
                      (opening == "{" && character == "}") || (opening == "[" && character == "]") else {
                    throw unsupported("Mismatched closing bracket.", input: input, at: index)
                }
                stack.removeLast()
                if stack.isEmpty, let start = rootStart {
                    let end = input.index(after: index)
                    result.append(JSONCandidate(
                        text: String(input[start..<end]),
                        originalUTF8Offset: baseOffset + input[..<start].utf8.count
                    ))
                    rootStart = nil
                }
            }
            index = input.index(after: index)
        }

        if let start = rootStart {
            throw unsupported("Incomplete JSON object or array.", input: input, at: start)
        }
        return result
    }

    /// 创建带原始 UTF-8 偏移的“不支持语法”错误。
    private static func unsupported(
        _ message: String,
        input: String,
        at index: String.Index
    ) -> JSONRepairer.RepairError {
        JSONRepairer.RepairError(
            kind: .unsupportedSyntax,
            message: message,
            byteOffset: input[..<index].utf8.count
        )
    }
}
