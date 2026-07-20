import Foundation
import Observation
import DotJSONCore

@MainActor
@Observable
final class EditorViewModel {
    /// 从 Finder、拖放或打开面板加载文档时可能产生的业务错误。
    enum DocumentError: Error, LocalizedError, Sendable {
        case nonFileURL
        case unsupportedFileExtension(String)

        var errorDescription: String? {
            switch self {
            case .nonFileURL:
                return "只能打开本地 JSON 文件。"
            case .unsupportedFileExtension(let fileExtension):
                let displayedExtension = fileExtension.isEmpty ? "无扩展名" : ".\(fileExtension)"
                return "不支持 \(displayedExtension) 文件，MVP 仅支持 .json。"
            }
        }
    }

    /// 导出文件时使用的序列化格式。
    enum ExportFormat: Sendable {
        /// 使用当前缩进选项生成可读 JSON。
        case formatted
        /// 移除无关空白，生成单行 JSON。
        case minified
    }

    nonisolated(unsafe) static weak var shared: EditorViewModel?

    var rawText: String = "" { didSet { reparse() } }
    var treeRoot: JSONNode? = nil
    var errorMessage: String? = nil
    var errorLineNumber: Int = 0
    var indent: JSONFormatter.Indent = .fourSpaces {
        didSet {
            guard indent != oldValue,
                  let formatted = try? JSONFormatter.format(rawText, indent: indent) else {
                return
            }

            // 缩进是文档显示格式的一部分，切换后立即重排，避免用户再点一次“格式化”。
            rawText = formatted
        }
    }
    var fileURL: URL? = nil
    var recentFiles: [URL] = []
    var autoFormatOnPaste = true
    var searchResults: [SearchResult] = []
    var activeSearchIndex: Int = 0
    private var savedText: String = ""

    var isModified: Bool { rawText != savedText }
    var searchMatchCount: Int { searchResults.count }
    var documentTitle: String { fileURL?.lastPathComponent ?? "Untitled" }

    init() { Self.shared = self }

    // MARK: - Actions
    func format() {
        guard let f = try? formattedOrRepaired(rawText) else { return }
        rawText = f
    }
    func minify() {
        guard let c = try? minifiedOrRepaired(rawText) else { return }
        rawText = c
    }
    func clear() {
        rawText = ""; treeRoot = nil; errorMessage = nil; errorLineNumber = 0
        fileURL = nil; savedText = ""; searchResults = []; activeSearchIndex = 0
    }
    func pasteAndFormat(_ text: String) {
        guard !text.isEmpty else { return }
        if autoFormatOnPaste, let f = try? formattedOrRepaired(text) {
            rawText = f
        } else {
            rawText = text
        }
    }

    // MARK: - Search
    func search(_ query: String) {
        searchResults = []; activeSearchIndex = 0
        guard !query.isEmpty else { return }
        let lines = rawText.components(separatedBy: .newlines)
        for (li, line) in lines.enumerated() {
            var start = line.startIndex
            while let r = line[start...].range(of: query) {
                let col = line.distance(from: line.startIndex, to: r.lowerBound) + 1
                searchResults.append(SearchResult(lineNumber: li+1, column: col,
                    matchedText: query, isKey: isKeyMatch(line: line, pos: col-1)))
                start = r.upperBound
            }
        }
    }
    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        activeSearchIndex = (activeSearchIndex + 1) % searchResults.count
    }
    func prevSearchResult() {
        guard !searchResults.isEmpty else { return }
        activeSearchIndex = activeSearchIndex == 0 ? searchResults.count - 1 : activeSearchIndex - 1
    }

    // MARK: - File
    /// 从系统文件入口加载一个 `.json` 文档。
    ///
    /// - Parameter url: Finder、Dock、拖放或打开面板传入的本地文件 URL。
    /// - Throws: URL 不是本地文件、扩展名不是 `.json`，或底层读取失败时抛出错误。
    func loadDocument(from url: URL) throws {
        guard url.isFileURL else { throw DocumentError.nonFileURL }
        let fileExtension = url.pathExtension
        guard fileExtension.caseInsensitiveCompare("json") == .orderedSame else {
            throw DocumentError.unsupportedFileExtension(fileExtension)
        }
        try load(from: url)
    }

    func load(from url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        rawText = text; fileURL = url; savedText = text; addRecent(url)
    }
    func save(to url: URL) throws {
        try rawText.write(to: url, atomically: true, encoding: .utf8)
        fileURL = url; savedText = rawText; addRecent(url)
    }

    /// 将当前有效 JSON 以指定格式导出到新文件。
    ///
    /// 导出与“另存为”语义不同：它不会改变当前文档 URL、原始文本或修改状态。
    ///
    /// - Parameters:
    ///   - url: 导出文件的目标 URL。
    ///   - format: 导出内容使用的格式化策略。
    /// - Throws: JSON 无效或目标文件无法写入时抛出底层错误。
    func export(to url: URL, format: ExportFormat) throws {
        let output: String
        switch format {
        case .formatted:
            output = try JSONFormatter.format(rawText, indent: indent)
        case .minified:
            output = try JSONFormatter.minify(rawText)
        }
        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 把文件系统错误转换为可展示状态。
    ///
    /// - Parameter error: 打开、保存或导出过程中产生的错误。
    ///
    /// 文件错误没有 JSON 行号，因此将 `errorLineNumber` 设为 0，防止界面伪造定位信息。
    func reportFileError(_ error: any Error) {
        errorMessage = error.localizedDescription
        errorLineNumber = 0
    }

    // MARK: - Private
    private func addRecent(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 10 { recentFiles = Array(recentFiles.prefix(10)) }
    }

    private func isKeyMatch(line: String, pos: Int) -> Bool {
        for (i, ch) in line.enumerated() {
            if i >= pos { break }
            if ch == ":" {
                var inStr = false
                for (j, c) in line.enumerated() where j < i {
                    if c == "\"" { inStr.toggle() }
                }
                if !inStr { return false }
            }
        }
        return true
    }

    private func reparse() {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            treeRoot = nil; errorMessage = nil; errorLineNumber = 0; return
        }
        do {
            treeRoot = try JSONParser.parse(rawText)
            errorMessage = nil
            errorLineNumber = 0
        } catch {
            treeRoot = nil
            errorMessage = error.localizedDescription
            errorLineNumber = parseErrorLine(from: error)
        }
    }

    /// 尝试把文本格式化为当前缩进风格，必要时先进行 Python 字面量修复。
    ///
    /// - Parameter text: 当前编辑器文本或剪贴板文本。
    /// - Returns: 格式化后的标准 JSON；无法安全修复时返回 `nil`。
    ///
    /// 先走标准 JSON 格式化可以保持合法 JSON 的既有行为；只有失败时才进入保守 repair，
    /// 避免把本来合法的 JSON 或用户正在编辑的半成品文本做额外解释。
    private func formattedOrRepaired(_ text: String) throws -> String {
        if let formatted = try? JSONFormatter.format(text, indent: indent) {
            return formatted
        }

        let repaired = try JSONRepairer.repair(text)
        return try JSONFormatter.format(repaired, indent: indent)
    }

    /// 尝试把文本压缩为单行标准 JSON，必要时先进行 Python 字面量修复。
    ///
    /// - Parameter text: 当前编辑器文本。
    /// - Returns: 单行标准 JSON；无法安全修复时返回 `nil`。
    ///
    /// 压缩入口与格式化入口共享同一条 repair 边界，确保按钮语义一致。
    private func minifiedOrRepaired(_ text: String) throws -> String {
        if let minified = try? JSONFormatter.minify(text) {
            return minified
        }

        let repaired = try JSONRepairer.repair(text)
        return try JSONFormatter.minify(repaired)
    }

    /// 将解析器的 UTF-8 字节偏移转换为从 1 开始的行号。
    ///
    /// - Parameter error: `JSONParser` 返回的结构化解析错误。
    /// - Returns: 对应错误行；底层没有定位信息时返回第 1 行。
    private func parseErrorLine(from error: JSONParser.ParseError) -> Int {
        guard let byteOffset = error.byteOffset else { return 1 }
        let safeOffset = min(max(byteOffset, 0), rawText.utf8.count)
        return rawText.utf8.prefix(safeOffset).reduce(into: 1) { line, byte in
            if byte == 0x0A { line += 1 }
        }
    }
}
