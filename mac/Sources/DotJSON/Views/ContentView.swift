import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var treeSearchText: String = ""
    @State private var treeSearchVisible = false
    @FocusState private var treeSearchFocused: Bool

    var body: some View {
        HSplitView {
            TextEditorView()
                .frame(minWidth: 300)
                .background(Color(hex: "#1e1e1e"))
            treePanel
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

    /// 右侧面板：树搜索栏 + 树视图。
    private var treePanel: some View {
        VStack(spacing: 0) {
            if treeSearchVisible {
                treeSearchBar
            }

            TreeView(onRequestFind: showTreeSearch)
        }
    }

    /// 仅在用户从右侧树请求查找时显示的深色搜索栏。
    private var treeSearchBar: some View {
        HStack(spacing: 6) {
            NativeTreeSearchField(
                text: $treeSearchText,
                onSearch: { value in
                    viewModel.searchTree(value)
                },
                onSubmit: { value in
                    if value == viewModel.treeSearchQuery,
                       viewModel.treeSearchMatchCount > 0 {
                        viewModel.nextTreeSearchResult()
                    } else {
                        viewModel.searchTree(value)
                    }
                },
                onCancel: closeTreeSearch
            )
            .focused($treeSearchFocused)
            .frame(height: 28)

            if viewModel.treeSearchMatchCount > 0 {
                Button(action: { viewModel.prevTreeSearchResult() }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: "#d4d4d4"))
                .help("上一个结果")

                Text("\(viewModel.activeTreeSearchIndex + 1)/\(viewModel.treeSearchMatchCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "#b8b8b8"))

                Button(action: { viewModel.nextTreeSearchResult() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: "#d4d4d4"))
                .help("下一个结果")
            } else if !treeSearchText.isEmpty {
                Text("无结果")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#b8b8b8"))
            }

            Button(action: closeTreeSearch) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: "#d4d4d4"))
            .help("关闭搜索")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: "#2d2d2d"))
    }

    /// 显示右侧搜索栏并在下一次布局完成后聚焦输入框。
    private func showTreeSearch() {
        treeSearchVisible = true
        DispatchQueue.main.async {
            treeSearchFocused = true
        }
    }

    /// 关闭右侧搜索栏、清空结果，并触发树视图恢复最新用户展开状态。
    private func closeTreeSearch() {
        treeSearchFocused = false
        treeSearchVisible = false
        treeSearchText = ""
        viewModel.searchTree("")
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

/// 树面板顶部的内嵌搜索框。
private struct NativeTreeSearchField: NSViewRepresentable {
    @Binding var text: String
    let onSearch: (String) -> Void
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSSearchField()
        field.placeholderAttributedString = NSAttributedString(
            string: "搜索 key / value",
            attributes: [.foregroundColor: NSColor(hex: "#858585")]
        )
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = NSColor(hex: "#1e1e1e")
        field.textColor = NSColor(hex: "#d4d4d4")
        field.font = .systemFont(ofSize: 12)
        field.focusRingType = .default
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSearch = onSearch
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onSearch: onSearch,
            onSubmit: onSubmit,
            onCancel: onCancel
        )
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var onSearch: (String) -> Void
        var onSubmit: (String) -> Void
        var onCancel: () -> Void
        /// 延迟搜索用的 work item，每次击键取消上次的再重新提交。
        private var searchWorkItem: DispatchWorkItem?

        init(
            text: Binding<String>,
            onSearch: @escaping (String) -> Void,
            onSubmit: @escaping (String) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.text = text
            self.onSearch = onSearch
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = field.stringValue
            syncText(value)
            // 200ms 防抖：连续输入时不上报，停手后才触发搜索
            searchWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.onSearch(value)
            }
            searchWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200), execute: workItem)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                searchWorkItem?.cancel()
                let value = control.stringValue
                syncText(value)
                onSubmit(value)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                searchWorkItem?.cancel()
                onCancel()
                return true
            }
            return false
        }

        private func syncText(_ value: String) {
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }
    }
}
