import SwiftUI
import AppKit

struct ToolbarView: ToolbarContent {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var searchText: String = ""

    var body: some ToolbarContent {
        // ── Left group ──
        ToolbarItemGroup {
            Button(action: { viewModel.format() }) {
                Label("格式化", systemImage: "text.alignleft")
            }
            .help("格式化 JSON（自动排版缩进）")

            Button(action: { viewModel.minify() }) {
                Label("压缩", systemImage: "text.aligncenter")
            }
            .help("压缩 JSON（移除所有空格和换行）")

            Picker("缩进", selection: Bindable(viewModel).indent) {
                ForEach(JSONFormatter.Indent.allCases, id: \.self) { o in
                    Text(o.label).tag(o)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)
            .help("选择缩进方式：2空格 / 4空格 / Tab")

            Divider()

            Button(action: { viewModel.clear() }) {
                Label("清空", systemImage: "trash")
            }
            .help("清空编辑器全部内容")

            Button(action: { pasteFromClipboard() }) {
                Label("粘贴", systemImage: "doc.on.clipboard")
            }
            .help("从剪贴板粘贴并自动格式化 JSON")
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button(action: { copyToClipboard() }) {
                Label("复制", systemImage: "doc.on.doc")
            }
            .help("复制全部内容到剪贴板")

            Menu {
                Button("导出格式化 JSON") {
                    export(format: .formatted)
                }
                Button("导出压缩 JSON") {
                    export(format: .minified)
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .help("将当前有效 JSON 导出为格式化或压缩文件")
        }

        // ── Right group: search ──
        ToolbarItemGroup {
            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("搜索", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 130)
                    .onSubmit { viewModel.search(searchText) }
                    .onChange(of: searchText) { _, v in viewModel.search(v) }
            }
            .help("搜索 JSON 中的 key 或 value，上下箭头切换结果")

            if viewModel.searchMatchCount > 0 {
                Button(action: { viewModel.prevSearchResult() }) {
                    Image(systemName: "chevron.up").font(.system(size: 9))
                }
                .help("上一个搜索结果")

                Text("\(viewModel.activeSearchIndex + 1)/\(viewModel.searchMatchCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                Button(action: { viewModel.nextSearchResult() }) {
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }
                .help("下一个搜索结果")
            }
        }
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        viewModel.pasteAndFormat(text)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.rawText, forType: .string)
    }

    /// 打开导出面板，并按用户选择的格式写入一个新 JSON 文件。
    ///
    /// - Parameter format: 格式化或压缩导出策略。
    private func export(format: EditorViewModel.ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let title = viewModel.documentTitle
        panel.nameFieldStringValue = title.lowercased().hasSuffix(".json")
            ? title
            : "\(title).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try viewModel.export(to: url, format: format)
            } catch {
                viewModel.reportFileError(error)
            }
        }
    }
}
