import SwiftUI
import AppKit

struct DotJSONCommands: Commands {

    private var vm: EditorViewModel? { EditorViewModel.shared }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open...") { openFile() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)

            Button("Save As...") { saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(after: .saveItem) {
            Divider()

            if let recent = vm?.recentFiles, !recent.isEmpty {
                Menu("Open Recent") {
                    ForEach(recent, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            loadDocument(from: url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        EditorViewModel.shared?.recentFiles = []
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
            guard r == .OK, let url = panel.url, let vm = EditorViewModel.shared else { return }
            do {
                try vm.loadDocument(from: url)
            } catch {
                vm.reportFileError(error)
            }
        }
    }

    private func save() {
        guard let vm = EditorViewModel.shared else { return }
        if let url = vm.fileURL {
            do {
                try vm.save(to: url)
            } catch {
                vm.reportFileError(error)
            }
        } else { saveAs() }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let documentTitle = EditorViewModel.shared?.documentTitle ?? "Untitled"
        panel.nameFieldStringValue = documentTitle.lowercased().hasSuffix(".json")
            ? documentTitle
            : "\(documentTitle).json"
        panel.begin { r in
            guard r == .OK, let url = panel.url, let vm = EditorViewModel.shared else { return }
            do {
                try vm.save(to: url)
            } catch {
                vm.reportFileError(error)
            }
        }
    }

    /// 从菜单的“最近打开”入口加载文档，并把错误反馈到当前编辑器。
    ///
    /// - Parameter url: 最近文件列表中的本地 JSON URL。
    private func loadDocument(from url: URL) {
        guard let vm = EditorViewModel.shared else { return }
        do {
            try vm.loadDocument(from: url)
        } catch {
            vm.reportFileError(error)
        }
    }
}
