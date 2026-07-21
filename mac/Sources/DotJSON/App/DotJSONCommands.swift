import SwiftUI
import AppKit

struct DotJSONCommands: Commands {

    private var workspace: WorkspaceViewModel? { WorkspaceViewModel.shared }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("新建") { workspace?.newTab() }
                .keyboardShortcut("n", modifiers: .command)

            Button("Open...") { openFile() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button("Save") { workspace?.saveActiveDocument() }
                .keyboardShortcut("s", modifiers: .command)

            Button("Save As...") { workspace?.saveActiveDocumentAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(after: .saveItem) {
            Divider()

            if let recent = workspace?.recentFiles, !recent.isEmpty {
                Menu("Open Recent") {
                    ForEach(recent, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            loadDocument(from: url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        workspace?.clearRecentFiles()
                    }
                }
            }
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { r in
            guard r == .OK, let url = panel.url, let ws = WorkspaceViewModel.shared else { return }
            ws.openDocument(from: url)
        }
    }

    private func loadDocument(from url: URL) {
        guard let ws = WorkspaceViewModel.shared else { return }
        ws.openDocument(from: url)
    }
}
