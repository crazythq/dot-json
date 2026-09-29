import SwiftUI
import AppKit

/// Diff pane editor: opens dropped files via callback (never inserts path strings into the buffer).
final class DiffPaneTextView: NSTextView {

    var onFileURLsDropped: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if FileDropPasteboard.containsFileURL(sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let fileURLs = FileDropPasteboard.fileURLs(from: sender.draggingPasteboard)
        if !fileURLs.isEmpty {
            onFileURLsDropped?(fileURLs)
            return true
        }
        return super.performDragOperation(sender)
    }
}

/// Monospaced Diff side editor wired to ViewModel inline text (no file-path drag insertion).
struct DiffSideTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onFileURLsDropped: ([URL]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = DiffPaneTextView()
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor(hex: "#cccccc")
        textView.insertionPointColor = NSColor(hex: "#cccccc")
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 1,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        textView.string = text
        textView.onFileURLsDropped = onFileURLsDropped

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let textView = scrollView.documentView as? DiffPaneTextView {
            textView.onFileURLsDropped = onFileURLsDropped
        }
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard !context.coordinator.isApplyingExternalUpdate else { return }
        if textView.string != text {
            context.coordinator.isApplyingExternalUpdate = true
            textView.string = text
            context.coordinator.isApplyingExternalUpdate = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?
        var isApplyingExternalUpdate = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? NSTextView else { return }
            let value = textView.string
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }
    }
}
