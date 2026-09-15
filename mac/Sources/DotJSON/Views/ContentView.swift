import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    @State private var treeSearchText: String = ""
    @State private var treeSearchVisible = false
    @FocusState private var treeSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 多标签页栏
            TabBarView()

            // 主编辑区域（根据标签页切换）
            if let doc = workspace.activeDocument {
                HSplitView {
                    TextEditorView()
                        .frame(minWidth: 300)
                        .background(Color(hex: "#1e1e1e"))
                    treePanel
                        .frame(minWidth: 200)
                        .background(Color(hex: "#252526"))
                }
                .environment(doc)
            } else {
                // 所有标签页已关闭时的空状态
                ZStack {
                    Color(hex: "#1a1a1a")
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(Color(hex: "#454545"))
                        Text("Open a JSON file to get started")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#858585"))
                        Button("New Document") {
                            workspace.newTab()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .background(Color(hex: "#1a1a1a"))
        .toolbar {
            ToolbarView()
        }
        .onOpenURL { url in
            workspace.openDocument(from: url)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            workspace.openDocument(from: url)
            return true
        }
        .sheet(isPresented: Binding(
            get: { workspace.isDiffPresented },
            set: { presented in
                if !presented { workspace.requestDismissDiff() }
            }
        )) {
            if let diffModel = workspace.diffViewModel {
                DiffView(model: diffModel)
                    .environment(workspace)
                    .interactiveDismissDisabled(diffModel.hasDirtyFileTargets)
            }
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
                    workspace.activeDocument?.searchTree(value)
                },
                onSubmit: { value in
                    guard let doc = workspace.activeDocument else { return }
                    if value == doc.treeSearchQuery,
                       doc.treeSearchMatchCount > 0 {
                        doc.nextTreeSearchResult()
                    } else {
                        doc.searchTree(value)
                    }
                },
                onCancel: closeTreeSearch
            )
            .focused($treeSearchFocused)
            .frame(height: 28)

            if let doc = workspace.activeDocument, doc.treeSearchMatchCount > 0 {
                Button(action: { doc.prevTreeSearchResult() }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: "#d4d4d4"))
                .help("Previous result")

                Text("\(doc.activeTreeSearchIndex + 1)/\(doc.treeSearchMatchCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "#b8b8b8"))

                Button(action: { doc.nextTreeSearchResult() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: "#d4d4d4"))
                .help("Next result")
            } else if !treeSearchText.isEmpty {
                Text("No results")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#b8b8b8"))
            }

            Button(action: closeTreeSearch) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: "#d4d4d4"))
            .help("Close search")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: "#2d2d2d"))
    }

    private func showTreeSearch() {
        treeSearchVisible = true
        DispatchQueue.main.async {
            treeSearchFocused = true
        }
    }

    private func closeTreeSearch() {
        treeSearchFocused = false
        treeSearchVisible = false
        treeSearchText = ""
        workspace.activeDocument?.searchTree("")
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
            string: "Search key / value",
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
