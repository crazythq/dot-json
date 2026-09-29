import AppKit
import DotJSONCore
import SwiftUI

/// Toolbar indent control — AppKit popup always shows the selected title (`2 spaces` / `4 spaces` / `Tab`).
struct IndentPopUpButton: NSViewRepresentable {
    static let toolbarWidth: CGFloat = 100

    @Bindable var document: EditorViewModel

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.toolbarWidth, height: 28))
        let popup = NSPopUpButton(
            frame: NSRect(x: 0, y: 0, width: Self.toolbarWidth, height: 26),
            pullsDown: false
        )
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
        popup.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(popup)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.toolbarWidth),
            container.heightAnchor.constraint(equalToConstant: 28),
            popup.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            popup.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        context.coordinator.popup = popup
        context.coordinator.syncSelection(on: popup, indent: document.indent)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.document = document
        guard let popup = context.coordinator.popup else { return }
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
