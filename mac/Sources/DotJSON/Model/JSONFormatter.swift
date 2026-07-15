import Foundation

/// Pure formatting logic — no UI, no platform code.
/// Format, minify, re-indent. Consumed by all platform targets.
enum JSONFormatter {

    enum Indent: Sendable, Equatable, CaseIterable {
        case twoSpaces
        case fourSpaces
        case tab

        var label: String {
            switch self {
            case .twoSpaces:  return "2 spaces"
            case .fourSpaces: return "4 spaces"
            case .tab:        return "Tab"
            }
        }

        var rawValue: String {
            switch self {
            case .twoSpaces:  return "  "
            case .fourSpaces: return "    "
            case .tab:        return "\t"
            }
        }
    }

    // MARK: - Public API

    /// Format (pretty-print) a JSON string with the given indent option.
    static func format(_ json: String, indent: Indent = .fourSpaces) throws -> String {
        let data = try validate(json)
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try prettyPrint(obj, indent: indent.rawValue)
    }

    /// Minify (compact) a JSON string to a single line.
    static func minify(_ json: String) throws -> String {
        let data = try validate(json)
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let compact = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(data: compact, encoding: .utf8) ?? json
    }

    /// Validate a JSON string. Returns the raw Data if valid.
    static func validate(_ json: String) throws -> Data {
        guard let data = json.data(using: .utf8) else {
            throw NSError(domain: "DotJSONCore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 encoding."])
        }
        _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return data
    }

    // MARK: - Private

    /// Recursively pretty-print a JSON value decoded by JSONSerialization.
    /// Uses array-wrapping to safely serialize leaf values (strings, numbers, null)
    /// since JSONSerialization.data(withJSONObject:) only accepts containers.
    private static func prettyPrint(_ value: Any, indent: String, level: Int = 0) throws -> String {
        let prefix = String(repeating: indent, count: level)
        let childPrefix = String(repeating: indent, count: level + 1)

        switch value {
        case let dict as [String: Any]:
            guard !dict.isEmpty else { return "{}" }
            let sorted = dict.sorted { $0.key < $1.key }
            let items = try sorted.map { (k, v) -> String in
                let val = try prettyPrint(v, indent: indent, level: level + 1)
                return "\(childPrefix)\(jsonEncodeLeaf(k)): \(val)"
            }
            return "{\n\(items.joined(separator: ",\n"))\n\(prefix)}"

        case let arr as [Any]:
            guard !arr.isEmpty else { return "[]" }
            let items = try arr.map { item -> String in
                try "\(childPrefix)\(prettyPrint(item, indent: indent, level: level + 1))"
            }
            return "[\n\(items.joined(separator: ",\n"))\n\(prefix)]"

        default:
            return jsonEncodeLeaf(value)
        }
    }

    /// Safely JSON-encode any leaf value by wrapping it in a single-element
    /// array, serializing, then stripping the brackets.
    private static func jsonEncodeLeaf(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: [value],
            options: [.sortedKeys, .withoutEscapingSlashes]
        ), var str = String(data: data, encoding: .utf8) else {
            return "null"
        }
        // str = '["hello"]' or '[42]' or '[true]' or '[null]'
        str.removeFirst() // drop '['
        str.removeLast()  // drop ']'
        return str
    }
}
