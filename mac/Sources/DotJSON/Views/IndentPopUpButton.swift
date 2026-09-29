import AppKit
import DotJSONCore
import SwiftUI

/// Compact standalone toolbar indent control (English titles: `2 spaces` / `4 spaces` / `Tab`).
struct IndentPopUpButton: NSViewRepresentable {
    /// Matches historical main toolbar picker width — fits longest label without a wide bar.
    static let toolbarWidth: CGFloat = 100
    private static let controlHeight: CGFloat = 22

    @Bindable var document: EditorViewModel

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(
            frame: NSRect(x: 0, y: 0, width: Self.toolbarWidth, height: Self.controlHeight),
            pullsDown: false
        )
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11)
        popup.autoenablesItems = true
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))

        for (index, option) in JSONFormatter.Indent.allCases.enumerated() {
            popup.addItem(withTitle: option.label)
            popup.item(at: index)?.tag = index
        }

        popup.setAccessibilityLabel("Indent")
        context.coordinator.popup = popup
        context.coordinator.syncSelection(on: popup, indent: document.indent)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.document = document
        context.coordinator.syncSelection(on: popup, indent: document.indent)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    @MainActor
    final class Coordinator: NSObject {
        var document: EditorViewModel
        weak var popup: NSPopUpButton?
        private var isApplyingSelection = false

        init(document: EditorViewModel) {
            self.document = document
        }

        func syncSelection(on popup: NSPopUpButton, indent: JSONFormatter.Indent) {
            guard let index = JSONFormatter.Indent.allCases.firstIndex(of: indent) else { return }
            guard popup.indexOfItem(withTag: index) >= 0 else { return }
            isApplyingSelection = true
            popup.selectItem(withTag: index)
            isApplyingSelection = false
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard !isApplyingSelection else { return }
            let index = sender.indexOfSelectedItem
            guard JSONFormatter.Indent.allCases.indices.contains(index) else { return }
            document.indent = JSONFormatter.Indent.allCases[index]
        }
    }
}
