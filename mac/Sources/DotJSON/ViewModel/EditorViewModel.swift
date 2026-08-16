import Foundation
import Observation
import DotJSONCore

@MainActor
@Observable
final class EditorViewModel: Identifiable {
    let id = UUID()

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

    var rawText: String = "" {
        didSet {
            reparse()
            refreshSearchResults(resetActiveIndex: false)
        }
    }
    var treeRoot: JSONNode? = nil
    var errorMessage: String? = nil
    var errorLineNumber: Int = 0
    var indent: JSONFormatter.Indent = .fourSpaces {
        didSet {
            guard indent != oldValue,
                  let formatted = try? JSONFormatter.format(rawText, indent: indent) else {
                return
            }
            rawText = formatted
        }
    }
    var fileURL: URL? = nil
    /// 未命名标签页的序号（0 表示未分配，仅文件标签页或默认值时为 0）。
    var untitledNumber: Int = 0
    /// 用户双击标签页自定义的名称；为空时回退到默认标题。
    var customTitle: String? = nil
    var autoFormatOnPaste = true
    var searchResults: [SearchResult] = []
    var activeSearchIndex: Int = 0
    private(set) var treeSearchMatches: [TreeSearchMatch] = []
    private(set) var activeTreeSearchIndex: Int = 0
    private(set) var treeSearchQuery: String = ""
    private var savedText: String = ""
    private var searchQuery: String = ""
    private var treeGeneration = 0
    private var treeSearchGeneration = 0

    /// 后台索引任务的返回值；generation 用于拒绝旧文档的过期索引。
    private struct TreeIndexBuild: Sendable {
        let generation: Int
        let index: TreeSearchIndex
    }

    /// 当前文档的后台树索引构建任务。
    @ObservationIgnored
    private var treeIndexTask: Task<TreeIndexBuild, Never>?

    var isModified: Bool { rawText != savedText }
    var searchMatchCount: Int { searchResults.count }
    var treeSearchMatchCount: Int { treeSearchMatches.count }
    /// 标签页标题：文件标签页显示文件名，未命名标签页显示 "Untitled N"。
    var documentTitle: String {
        if let customTitle {
            return customTitle
        }
        if let url = fileURL {
            return url.lastPathComponent
        }
        return untitledNumber > 0 ? "Untitled \(untitledNumber)" : "Untitled"
    }
    /// 当前内容是否为可解析的非空 JSON（用于关闭前的二次确认）。
    var hasValidJSONContent: Bool { treeRoot != nil }
    var activeSearchResult: SearchResult? {
        guard searchResults.indices.contains(activeSearchIndex) else { return nil }
        return searchResults[activeSearchIndex]
    }
    var activeTreeSearchMatch: TreeSearchMatch? {
        guard treeSearchMatches.indices.contains(activeTreeSearchIndex) else { return nil }
        return treeSearchMatches[activeTreeSearchIndex]
    }

    /// 取消后台索引任务，在标签页关闭时调用。
    func cancelBackgroundTasks() {
        treeIndexTask?.cancel()
        treeIndexTask = nil
    }

    // MARK: - Actions
    /// 设置标签页的自定义显示名称；空字符串会清除自定义名称，恢复默认标题。
    ///
    /// - Parameter title: 自定义标题（首尾空白会被裁剪）。
    func rename(to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        customTitle = trimmed.isEmpty ? nil : trimmed
    }

    func format() {
        guard let f = try? formattedOrRepaired(rawText) else { return }
        rawText = f
    }
    func minify() {
        guard let c = try? minifiedOrRepaired(rawText) else { return }
        rawText = c
    }
    func clear() {
        treeSearchQuery = ""
        treeSearchMatches = []
        activeTreeSearchIndex = 0
        rawText = ""; treeRoot = nil; errorMessage = nil; errorLineNumber = 0
        fileURL = nil; savedText = ""; searchQuery = ""; searchResults = []; activeSearchIndex = 0
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
        searchQuery = query
        refreshSearchResults(resetActiveIndex: true)
    }
    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        activeSearchIndex = (activeSearchIndex + 1) % searchResults.count
    }
    func prevSearchResult() {
        guard !searchResults.isEmpty else { return }
        activeSearchIndex = activeSearchIndex == 0 ? searchResults.count - 1 : activeSearchIndex - 1
    }

    @discardableResult
    func searchTree(_ query: String) -> Task<Void, Never>? {
        treeSearchQuery = query
        treeSearchGeneration += 1
        let requestedSearchGeneration = treeSearchGeneration

        guard !query.isEmpty else {
            treeSearchMatches = []
            activeTreeSearchIndex = 0
            return nil
        }
        guard let treeIndexTask else {
            treeSearchMatches = []
            activeTreeSearchIndex = 0
            return nil
        }

        let requestedTreeGeneration = treeGeneration
        return Task { [weak self] in
            await self?.performTreeSearch(
                query: query,
                requestedTreeGeneration: requestedTreeGeneration,
                requestedSearchGeneration: requestedSearchGeneration,
                treeIndexTask: treeIndexTask
            )
        }
    }

    private func performTreeSearch(
        query: String,
        requestedTreeGeneration: Int,
        requestedSearchGeneration: Int,
        treeIndexTask: Task<TreeIndexBuild, Never>
    ) async {
        let build = await treeIndexTask.value
        guard requestedTreeGeneration == treeGeneration,
              build.generation == treeGeneration,
              requestedSearchGeneration == treeSearchGeneration,
              query == treeSearchQuery else {
            return
        }

        let matches = await Task.detached(priority: .userInitiated) {
            build.index.matches(query: query)
        }.value
        guard requestedTreeGeneration == treeGeneration,
              build.generation == treeGeneration,
              requestedSearchGeneration == treeSearchGeneration,
              query == treeSearchQuery else {
            return
        }

        treeSearchMatches = matches
        activeTreeSearchIndex = 0
    }

    func nextTreeSearchResult() {
        guard !treeSearchMatches.isEmpty else { return }
        activeTreeSearchIndex = (activeTreeSearchIndex + 1) % treeSearchMatches.count
    }

    func prevTreeSearchResult() {
        guard !treeSearchMatches.isEmpty else { return }
        activeTreeSearchIndex = activeTreeSearchIndex == 0
            ? treeSearchMatches.count - 1
            : activeTreeSearchIndex - 1
    }

    // MARK: - File
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
        rawText = text; fileURL = url; savedText = text
    }
    func save(to url: URL) throws {
        try rawText.write(to: url, atomically: true, encoding: .utf8)
        fileURL = url; savedText = rawText
    }

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

    func reportFileError(_ error: any Error) {
        errorMessage = error.localizedDescription
        errorLineNumber = 0
    }

    // MARK: - Private
    private func refreshSearchResults(resetActiveIndex: Bool) {
        searchResults = []
        if resetActiveIndex { activeSearchIndex = 0 }
        guard !searchQuery.isEmpty else {
            activeSearchIndex = 0
            return
        }

        var start = rawText.startIndex
        while let range = rawText[start...].range(of: searchQuery) {
            let location = lineAndColumn(for: range.lowerBound)
            let nsRange = NSRange(range, in: rawText)
            let line = lineText(containing: range.lowerBound)
            searchResults.append(SearchResult(
                lineNumber: location.line,
                column: location.column,
                matchedText: searchQuery,
                isKey: isKeyMatch(line: line, pos: location.column - 1),
                range: nsRange
            ))
            start = range.upperBound
        }

        guard !searchResults.isEmpty else {
            activeSearchIndex = 0
            return
        }
        activeSearchIndex = min(activeSearchIndex, searchResults.count - 1)
    }

    private func lineAndColumn(for index: String.Index) -> (line: Int, column: Int) {
        let prefix = rawText[..<index]
        let line = prefix.reduce(1) { count, character in
            character.isNewline ? count + 1 : count
        }
        let lineStart = prefix.lastIndex(where: \.isNewline).map {
            rawText.index(after: $0)
        } ?? rawText.startIndex
        return (line, rawText.distance(from: lineStart, to: index) + 1)
    }

    private func lineText(containing index: String.Index) -> String {
        let lineStart = rawText[..<index].lastIndex(where: \.isNewline).map {
            rawText.index(after: $0)
        } ?? rawText.startIndex
        let lineEnd = rawText[index...].firstIndex(where: \.isNewline) ?? rawText.endIndex
        return String(rawText[lineStart..<lineEnd])
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
            treeRoot = nil
            errorMessage = nil
            errorLineNumber = 0
            scheduleTreeSearchIndex(for: nil)
            return
        }
        do {
            let parsedRoot = try JSONParser.parse(rawText)
            treeRoot = parsedRoot
            errorMessage = nil
            errorLineNumber = 0
            scheduleTreeSearchIndex(for: parsedRoot)
        } catch {
            treeRoot = nil
            errorMessage = error.localizedDescription
            errorLineNumber = parseErrorLine(from: error)
            scheduleTreeSearchIndex(for: nil)
        }
    }

    private func scheduleTreeSearchIndex(for root: JSONNode?) {
        treeGeneration += 1
        let requestedTreeGeneration = treeGeneration
        treeSearchGeneration += 1
        treeSearchMatches = []
        activeTreeSearchIndex = 0
        treeIndexTask?.cancel()
        treeIndexTask = nil

        guard let root else { return }
        treeIndexTask = Task.detached(priority: .userInitiated) {
            TreeIndexBuild(
                generation: requestedTreeGeneration,
                index: TreeSearchIndex(root: root)
            )
        }

        let pendingQuery = treeSearchQuery
        if !pendingQuery.isEmpty {
            searchTree(pendingQuery)
        }
    }

    private func formattedOrRepaired(_ text: String) throws -> String {
        if let formatted = try? JSONFormatter.format(text, indent: indent) {
            return formatted
        }
        let repaired = try JSONRepairer.repair(text)
        return try JSONFormatter.format(repaired, indent: indent)
    }

    private func minifiedOrRepaired(_ text: String) throws -> String {
        if let minified = try? JSONFormatter.minify(text) {
            return minified
        }
        let repaired = try JSONRepairer.repair(text)
        return try JSONFormatter.minify(repaired)
    }

    private func parseErrorLine(from error: JSONParser.ParseError) -> Int {
        guard let byteOffset = error.byteOffset else { return 1 }
        let safeOffset = min(max(byteOffset, 0), rawText.utf8.count)
        return rawText.utf8.prefix(safeOffset).reduce(into: 1) { line, byte in
            if byte == 0x0A { line += 1 }
        }
    }
}
