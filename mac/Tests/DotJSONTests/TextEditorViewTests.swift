import AppKit
import Testing
@testable import DotJSON

@MainActor
struct TextEditorViewTests {
    @Test func standardPasteRoutesClipboardTextThroughHandler() {
        let pasteboard = NSPasteboard(name: .init("DotJSONTests.Paste"))
        pasteboard.clearContents()
        pasteboard.setString(#"{"name":"DotJSON"}"#, forType: .string)
        let textView = JSONTextView()
        textView.sourcePasteboard = pasteboard
        var receivedText: String?
        textView.onPaste = { receivedText = $0 }

        textView.paste(nil)

        #expect(receivedText == #"{"name":"DotJSON"}"#)
    }

    @Test func pasteDoesNothingWhenClipboardHasNoPlainText() {
        let pasteboard = NSPasteboard(name: .init("DotJSONTests.EmptyPaste"))
        pasteboard.clearContents()
        let textView = JSONTextView()
        textView.sourcePasteboard = pasteboard
        textView.string = "original"
        var handlerWasCalled = false
        textView.onPaste = { _ in handlerWasCalled = true }

        textView.paste(nil)

        #expect(!handlerWasCalled)
        #expect(textView.string == "original")
    }

    @Test func textViewConfiguresAResizableScrollableDocument() {
        let textView = JSONTextView()

        textView.configureForScrolling()

        #expect(textView.isVerticallyResizable)
        #expect(!textView.isHorizontallyResizable)
        #expect(textView.textContainer?.widthTracksTextView == true)
        #expect(textView.maxSize.width == .greatestFiniteMagnitude)
    }

    @Test func typedTextUsesTheDarkThemeForegroundColor() throws {
        let textView = JSONTextView()

        textView.configureForScrolling()

        let color = try #require(
            textView.typingAttributes[.foregroundColor] as? NSColor
        )
        #expect(color == NSColor(hex: "#d4d4d4"))
    }

    /// 验证左侧 Cmd+F 使用 AppKit 约定的明确查找动作，而不是传入无法判定动作的 nil。
    @Test func findShortcutUsesShowFindInterfaceActionTag() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/TextEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("NSTextFinder.Action.showFindInterface.rawValue"))
        #expect(source.contains("self === responder || responder.isDescendant(of: self)"))
        #expect(!source.contains("performFindPanelAction(nil)"))
    }

    @Test func programmaticTextKeepsDarkThemeForegroundColor() throws {
        let textView = JSONTextView()

        textView.setPlainText(#"{"visible":true}"#)

        let color = try #require(
            textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil)
                as? NSColor
        )
        #expect(color == NSColor(hex: "#d4d4d4"))
        #expect(textView.string == #"{"visible":true}"#)
    }

    @Test func textChangeReappliesDarkThemeForegroundColorToExistingEditorText() throws {
        let viewModel = EditorViewModel()
        let textView = JSONTextView()
        let coordinator = TextEditorView.Coordinator(viewModel: viewModel)
        coordinator.textView = textView
        textView.configureForScrolling()
        textView.string = #"{"a":[]}"#
        textView.textStorage?.addAttribute(
            .foregroundColor,
            value: NSColor.black,
            range: NSRange(location: 0, length: textView.string.count)
        )

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification))

        let color = try #require(
            textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil)
                as? NSColor
        )
        #expect(color == NSColor(hex: "#d4d4d4"))
        #expect(viewModel.rawText == #"{"a":[]}"#)
        #expect(viewModel.treeRoot != nil)
    }

    @Test func updateSynchronizesThemeWhenEditorTextAlreadyMatchesViewModelText() throws {
        let viewModel = EditorViewModel()
        let textView = JSONTextView()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let coordinator = TextEditorView.Coordinator(viewModel: viewModel)
        textView.configureForScrolling()
        scrollView.documentView = textView
        viewModel.rawText = #"{"already":"synced"}"#
        textView.string = viewModel.rawText
        textView.textStorage?.addAttribute(
            .foregroundColor,
            value: NSColor.black,
            range: NSRange(location: 0, length: textView.string.count)
        )

        coordinator.synchronizeTextView(
            textView,
            rawText: viewModel.rawText,
            in: scrollView
        )

        let color = try #require(
            textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil)
                as? NSColor
        )
        #expect(color == NSColor(hex: "#d4d4d4"))
        #expect(textView.string == viewModel.rawText)
    }

    @Test func documentViewGetsNonZeroFrameAfterScrollViewLayout() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let textView = JSONTextView()
        textView.configureForScrolling()
        scrollView.documentView = textView
        textView.setPlainText(#"{"visible":true}"#)

        textView.updateDocumentSize(in: scrollView)

        #expect(textView.frame.width >= scrollView.contentSize.width)
        #expect(textView.frame.height >= scrollView.contentSize.height)
        #expect(textView.frame.width > 0)
        #expect(textView.frame.height > 0)
    }

    @Test func scrollOffsetChangeDoesNotRecalculateDocumentFrameWhenViewportSizeIsUnchanged() {
        let viewModel = EditorViewModel()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let textView = JSONTextView()
        let coordinator = TextEditorView.Coordinator(viewModel: viewModel)
        textView.configureForScrolling()
        scrollView.documentView = textView

        coordinator.synchronizeTextView(
            textView,
            rawText: (0..<80).map { #"{"line":\#($0)}"# }.joined(separator: "\n"),
            in: scrollView
        )
        let scrollAdjustedFrame = NSRect(
            x: textView.frame.origin.x,
            y: -120,
            width: textView.frame.width,
            height: textView.frame.height
        )
        textView.frame = scrollAdjustedFrame

        coordinator.updateDocumentSizeIfViewportChanged(textView, in: scrollView)

        #expect(textView.frame == scrollAdjustedFrame)
    }

    @Test func treeReloadPublishesRootBeforeDataSourceIsQueried() throws {
        let viewModel = EditorViewModel()
        viewModel.rawText = #"{"features":{"tree":true},"items":[1,2,3]}"#
        let outlineView = NSOutlineView()
        outlineView.addTableColumn(NSTableColumn(identifier: .init("TreeColumn")))
        let coordinator = TreeView.Coordinator()
        coordinator.outlineView = outlineView
        outlineView.dataSource = coordinator
        outlineView.delegate = coordinator

        coordinator.reloadIfNeeded(viewModel: viewModel)

        #expect(outlineView.numberOfRows >= 1)
    }

    @Test func treeReloadClearsStaleRowsAfterJSONBecomesInvalid() {
        let viewModel = EditorViewModel()
        let outlineView = NSOutlineView()
        outlineView.addTableColumn(NSTableColumn(identifier: .init("TreeColumn")))
        let coordinator = TreeView.Coordinator()
        coordinator.outlineView = outlineView
        outlineView.dataSource = coordinator
        outlineView.delegate = coordinator
        viewModel.rawText = #"{"valid":true}"#
        coordinator.reloadIfNeeded(viewModel: viewModel)
        #expect(outlineView.numberOfRows >= 1)

        viewModel.rawText = #"{"invalid": value}"#
        coordinator.reloadIfNeeded(viewModel: viewModel)

        #expect(outlineView.numberOfRows == 0)
    }

    /// 验证按稳定 ID 重新取得的树项仍能控制 NSOutlineView 中已经存在的同一节点。
    @Test func equivalentTreeItemCanExpandExistingOutlineNode() throws {
        let viewModel = EditorViewModel()
        viewModel.rawText = #"{"outer":{"target":1}}"#
        let outlineView = NSOutlineView()
        outlineView.addTableColumn(NSTableColumn(identifier: .init("TreeColumn")))
        let coordinator = TreeView.Coordinator()
        coordinator.outlineView = outlineView
        outlineView.dataSource = coordinator
        outlineView.delegate = coordinator
        coordinator.reloadIfNeeded(viewModel: viewModel)
        let root = try #require(viewModel.treeRoot)
        let tree = JSONTree(root: root)
        let outerID = TreeNodeID(components: [.key("outer")])
        let equivalentOuterItem = try #require(tree.item(for: outerID))

        outlineView.expandItem(equivalentOuterItem)

        #expect(outlineView.isItemExpanded(equivalentOuterItem))
        #expect(outlineView.numberOfRows == 3)
    }

    /// 搜索结果切换只能处理展开集合的差异，不能遍历大纲的全部可见行。
    ///
    /// 大 JSON 展开根节点后可能拥有数十万行；若每次切换结果都扫描
    /// `numberOfRows`，索引本身再快也无法满足三秒内响应的交互要求。
    @Test func treeSearchExpansionAppliesOnlyStateDifference() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/TreeView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("desiredExpandedIDs.subtracting(lastAppliedExpandedIDs)"))
        #expect(source.contains("lastAppliedExpandedIDs.subtracting(desiredExpandedIDs)"))
        #expect(!source.contains("stride(from: outlineView.numberOfRows - 1"))
    }

    @Test func rulerStoresErrorMetadataForHoverAndHighlight() {
        let ruler = LineNumberRulerView(scrollView: NSScrollView())

        ruler.updateError(lineNumber: 3, message: "Invalid value")

        #expect(ruler.errorLineNumber == 3)
        #expect(ruler.errorMessage == "Invalid value")
    }

    @Test func lineNumberGutterUsesTopOriginCoordinates() {
        let ruler = LineNumberRulerView(scrollView: NSScrollView())

        #expect(ruler.isFlipped)
    }

    @Test func textChangeImmediatelyUpdatesRulerErrorMetadata() {
        let viewModel = EditorViewModel()
        let textView = JSONTextView()
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let ruler = LineNumberRulerView(scrollView: scrollView)
        ruler.clientView = textView
        let coordinator = TextEditorView.Coordinator(viewModel: viewModel)
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.lineNumberRulerView = ruler
        textView.string = "{\n  \"name\": invalid\n}"

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification))

        #expect(ruler.errorLineNumber == 2)
        #expect(ruler.errorMessage?.contains("line 2") == true)
    }

    @Test func searchHighlightsAllMatchesAndMarksActiveMatchInEditor() throws {
        let textView = JSONTextView()
        textView.configureForScrolling()
        textView.setPlainText(#"{"name":"Task","description":"Task runner"}"#)
        let firstRange = NSRange(location: 9, length: 4)
        let secondRange = NSRange(location: 30, length: 4)
        let results = [
            SearchResult(lineNumber: 1, column: 10, matchedText: "Task", isKey: false, range: firstRange),
            SearchResult(lineNumber: 1, column: 31, matchedText: "Task", isKey: false, range: secondRange),
        ]

        textView.applySearchHighlights(results: results, activeIndex: 1)

        let firstBackground = try #require(
            textView.textStorage?.attribute(.backgroundColor, at: firstRange.location, effectiveRange: nil)
                as? NSColor
        )
        let secondBackground = try #require(
            textView.textStorage?.attribute(.backgroundColor, at: secondRange.location, effectiveRange: nil)
                as? NSColor
        )
        #expect(firstBackground == JSONTextView.searchMatchColor)
        #expect(secondBackground == JSONTextView.activeSearchMatchColor)
    }

    @Test func treeViewSourceConfiguresWrappingRowsAndStableSearchSelection() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/TreeView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("outlineView.usesAutomaticRowHeights = true"))
        #expect(source.contains("textField.lineBreakMode = .byWordWrapping"))
        #expect(source.contains("textField.maximumNumberOfLines = 0"))
        #expect(source.contains("private func selectAndScroll("))
        #expect(source.contains("private func applySearchHighlights("))
        #expect(source.contains("TreeExpansionState()"))
        #expect(source.contains("outlineView.rows(in: outlineView.visibleRect)"))
        #expect(source.contains("override var acceptsFirstResponder: Bool"))
        #expect(source.contains("window?.makeFirstResponder(self)"))
    }
}
