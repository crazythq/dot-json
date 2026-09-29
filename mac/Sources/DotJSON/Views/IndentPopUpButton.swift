import AppKit
import DotJSONCore
import SwiftUI

/// Toolbar indent control — AppKit popup always shows the selected title (`2 spaces` / `4 spaces` / `Tab`).
struct IndentPopUpButton: NSViewRepresentable {
    @Bindable var document: EditorViewModel

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.bezelStyle = .rounded
        popup.controlSize = .regular
        popup.font = .systemFont(ofSize: 13)
        popup.autoenablesItems = true
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))

        for (index, option) in JSONFormatter.Indent.allCases.enumerated() {
            popup.addItem(withTitle: option.label)
            popup.item(at: index)?.tag = index
        }

        popup.setAccessibilityLabel("Indent")
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

        init(document: EditorViewModel) {
            self.document = document
        }

        func syncSelection(on popup: NSPopUpButton, indent: JSONFormatter.Indent) {
            guard let index = JSONFormatter.Indent.allCases.firstIndex(of: indent) else { return }
            guard popup.indexOfItem(withTag: index) >= 0 else { return }
            popup.selectItem(withTag: index)
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard JSONFormatter.Indent.allCases.indices.contains(index) else { return }
            document.indent = JSONFormatter.Indent.allCases[index]
        }
    }
}
