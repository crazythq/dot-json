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

            // 缩进是文档显示格式的一部分，切换后立即重排，避免用户再点一次“格式化”。
            rawText = formatted
        }
    }
    var fileURL: URL? = nil
    var recentFiles: [URL] = []
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
    var documentTitle: String { fileURL?.lastPathComponent ?? "Untitled" }
    var activeSearchResult: SearchResult? {
        guard searchResults.indices.contains(activeSearchIndex) else { return nil }
        return searchResults[activeSearchIndex]
    }
    var activeTreeSearchMatch: TreeSearchMatch? {
        guard treeSearchMatches.indices.contains(activeTreeSearchIndex) else { return nil }
        return treeSearchMatches[activeTreeSearchIndex]
    }

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

    /// 发起一次右侧面板搜索，并返回可供测试或立即提交等待的任务。
    ///
    /// - Parameter query: 区分大小写的 key/value 查询文本；空字符串清空结果。
    /// - Returns: 非空查询对应的后台任务；空查询完成同步清理后返回 `nil`。
    ///
    /// 查询版本必须在这个同步入口中生成。如果把版本生成放进外层 `Task`，两个连续用户请求
    /// 可能被调度器逆序启动，较早的请求反而取得更大的版本号并覆盖新结果。
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

    /// 等待索引并执行查询，只允许仍为最新的文档和请求发布结果。
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

    /// 切换到下一条右侧树搜索结果，并在末尾循环到第一条。
    func nextTreeSearchResult() {
        guard !treeSearchMatches.isEmpty else { return }
        activeTreeSearchIndex = (activeTreeSearchIndex + 1) % treeSearchMatches.count
    }

    /// 切换到上一条右侧树搜索结果，并在第一条向前时循环到末尾。
    func prevTreeSearchResult() {
        guard !treeSearchMatches.isEmpty else { return }
        activeTreeSearchIndex = activeTreeSearchIndex == 0
            ? treeSearchMatches.count - 1
            : activeTreeSearchIndex - 1
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

    /// 根据当前搜索词重新计算所有命中的源码位置。
    ///
    /// - Parameter resetActiveIndex: 新查询需要回到第一条；文档内容变化时只夹紧现有索引。
    ///
    /// `NSTextView` 使用 UTF-16 坐标，而用户看到的行列按 Swift 字符计数展示；
    /// 因此这里同时保存两套坐标，避免 UI 层各自重复推导后出现偏移。
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

    /// 计算指定字符索引对应的用户可见行列。
    ///
    /// - Parameter index: `rawText` 中的字符索引。
    /// - Returns: 从 1 开始的行列号。
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

    /// 取出指定位置所在的完整文本行，用于判断命中是否在 key 区域。
    ///
    /// - Parameter index: `rawText` 中的字符索引。
    /// - Returns: 不包含换行符的当前行文本。
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

    /// 为新树启动后台索引构建，并使旧文档、旧查询结果立即失效。
    ///
    /// - Parameter root: 当前有效 JSON 根节点；`nil` 表示清除索引。
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

        // 编辑器内容变化时，保持搜索框查询不变，并在新索引完成后刷新结果。
        let pendingQuery = treeSearchQuery
        if !pendingQuery.isEmpty {
            searchTree(pendingQuery)
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
