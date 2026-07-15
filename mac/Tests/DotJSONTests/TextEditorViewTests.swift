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

    @Test func rulerStoresErrorMetadataForHoverAndHighlight() {
        let ruler = LineNumberRulerView(scrollView: NSScrollView())

        ruler.updateError(lineNumber: 3, message: "Invalid value")

        #expect(ruler.errorLineNumber == 3)
        #expect(ruler.errorMessage == "Invalid value")
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
}
