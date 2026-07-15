import SwiftUI

struct ContentView: View {
    @Environment(EditorViewModel.self) private var viewModel

    var body: some View {
        HSplitView {
            TextEditorView()
                .frame(minWidth: 300)
                .background(Color(hex: "#1e1e1e"))
                .overlay(alignment: .topTrailing) {
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: "#fca5a5"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#3b1515"))
                            .cornerRadius(4)
                            .padding(6)
                    }
                }
            TreeView()
                .frame(minWidth: 200)
                .background(Color(hex: "#252526"))
        }
        .background(Color(hex: "#1a1a1a"))
        .toolbar {
            ToolbarView()
        }
        .onOpenURL { url in
            openDocument(from: url)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            openDocument(from: url)
            return true
        }
    }

    /// 处理 Finder、Dock 或窗口拖放传入的本地文件 URL。
    ///
    /// - Parameter url: 待加载的本地 JSON 文件。
    private func openDocument(from url: URL) {
        do {
            try viewModel.loadDocument(from: url)
        } catch {
            viewModel.reportFileError(error)
        }
    }
}
