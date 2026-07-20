import SwiftUI
import AppKit
import DotJSONCore

/// 工具栏紧凑布局参数。
///
/// 这里集中保存搜索框宽度和控件间距，避免 SwiftUI 外层 frame 与 AppKit intrinsic size 漂移。
private enum ToolbarMetrics {
    static let searchFieldWidth: CGFloat = 140
    static let controlSpacing: CGFloat = 6
}

struct ToolbarView: ToolbarContent {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var searchText: String = ""
    @AppStorage("toolbarShowsText") private var toolbarShowsText: Bool = true

    var body: some ToolbarContent {
        // ── Left group ──
        ToolbarItemGroup {
            Button(action: { viewModel.format() }) {
                Label("格式化", systemImage: "text.alignleft")
            }
            .help("格式化 JSON")

            Button(action: { viewModel.minify() }) {
                Label("压缩", systemImage: "text.aligncenter")
            }
            .help("压缩 JSON")

            Picker("缩进", selection: Bindable(viewModel).indent) {
                ForEach(JSONFormatter.Indent.allCases, id: \.self) { o in
                    Text(o.label).tag(o)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)
            .help("缩进：2 空格 / 4 空格 / Tab")
        }

        // ── 文件操作 ──
        ToolbarItem {
            ControlGroup {
                toolbarIconButton("清空", systemImage: "trash") {
                    viewModel.clear()
                }
                .help("清空内容")

                toolbarIconButton("粘贴", systemImage: "doc.on.clipboard") {
                    pasteFromClipboard()
                }
                .help("粘贴并格式化")
                .keyboardShortcut("v", modifiers: [.command, .shift])

                toolbarIconButton("复制", systemImage: "doc.on.doc") {
                    copyToClipboard()
                }
                .help("复制到剪贴板")
            }
            .controlGroupStyle(.navigation)
            .controlSize(.large)
        }

        // ── 导入/导出 ──
        ToolbarItem {
            ControlGroup {
                toolbarIconButton("导入", systemImage: "square.and.arrow.down") {
                    importDocument()
                }
                .help("导入 JSON 文件")

                Menu {
                    Button("导出格式化 JSON") {
                        export(format: .formatted)
                    }
                    Button("导出压缩 JSON") {
                        export(format: .minified)
                    }
                } label: {
                    toolbarIconLabel("导出", systemImage: "square.and.arrow.up")
                }
                .help("导出 JSON")
            }
            .controlGroupStyle(.navigation)
            .controlSize(.large)
        }

        // ── Right group: search ──
        ToolbarItem(placement: .principal) {
            HStack(spacing: ToolbarMetrics.controlSpacing) {
                NativeToolbarSearchField(text: $searchText) { value in
                    viewModel.search(value)
                }
                .frame(width: ToolbarMetrics.searchFieldWidth, height: 32)
                .help("搜索 Key 或值（↑↓切换）")

                if viewModel.searchMatchCount > 0 {
                    Button(action: { viewModel.prevSearchResult() }) {
                        Image(systemName: "chevron.up").font(.system(size: 9))
                    }
                    .help("上一个结果")

                    Text("\(viewModel.activeSearchIndex + 1)/\(viewModel.searchMatchCount)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    Button(action: { viewModel.nextSearchResult() }) {
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .help("下一个结果")
                }
            }
        }
    }

    /// 创建原生工具栏中的纯图标按钮，并固定图标画布以避免 SF Symbol 在按钮槽位中偏移。
    ///
    /// - Parameters:
    ///   - title: 按钮的无障碍名称和语义标题。
    ///   - systemImage: SF Symbols 图标名称。
    ///   - action: 用户点击按钮时执行的操作。
    /// - Returns: 一个适合放入 `ToolbarItemGroup` 的图标按钮。
    private func toolbarIconButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarIconLabel(title, systemImage: systemImage)
        }
        .controlSize(.large)
        .accessibilityLabel(title)
    }

    /// 创建工具栏图标标签，统一按钮和菜单入口的图标尺寸、上下排版与文字隐藏策略。
    ///
    /// - Parameters:
    ///   - title: 图标对应的语义标题。
    ///   - systemImage: SF Symbols 图标名称。
    /// - Returns: 一个图标在上、文字在下的紧凑标签视图；用户可通过右键菜单隐藏文字。
    private func toolbarIconLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(ToolbarIconLabelStyle(showsText: toolbarShowsText))
            .contentShape(Rectangle())
            .contextMenu {
                Toggle("显示文字", isOn: $toolbarShowsText)
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

    /// 打开系统文件选择框，并将选中的 JSON 文件加载到当前编辑器。
    ///
    /// 用户取消选择时不改变当前编辑器状态；读取或格式校验失败时，复用视图模型的错误提示。
    private func importDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try viewModel.loadDocument(from: url)
            } catch {
                viewModel.reportFileError(error)
            }
        }
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

/// 工具栏主区域的竖排图标标签样式。
///
/// 保留 `Label` 语义，让 macOS 在工具栏溢出菜单中仍可使用原生 title/image 表示；
/// 主工具栏区域则通过样式把图标放在文字上方。
private struct ToolbarIconLabelStyle: LabelStyle {
    let showsText: Bool

    /// 生成竖排工具栏标签。
    ///
    /// - Parameter configuration: SwiftUI 提供的语义化 `Label` 标题和图标。
    /// - Returns: 固定尺寸的图标上、文字下标签；隐藏文字时保留紧凑图标画布。
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 2) {
            configuration.icon
                .font(.system(size: 15, weight: .regular))
                .frame(width: 18, height: 18, alignment: .center)

            if showsText {
                configuration.title
                    .font(.system(size: 9, weight: .regular))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .frame(width: 42, height: showsText ? 42 : 30, alignment: .center)
    }
}

/// 使用 AppKit 原生搜索框承接 macOS 工具栏搜索样式。
///
/// 固定 intrinsic size 是必要的：SwiftUI toolbar 会在聚焦或窗口宽度变化时重新询问视图尺寸；
/// 如果搜索框只有默认最小尺寸，系统可能把它压缩成只剩放大镜的工具栏项。
private struct NativeToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    let onSearch: (String) -> Void

    /// 创建固定宽度的原生搜索框，并连接文本变化事件。
    ///
    /// - Parameter context: SwiftUI 提供的视图上下文。
    /// - Returns: 一个不会在聚焦时坍缩为图标的 `NSSearchField`。
    func makeNSView(context: Context) -> FixedToolbarSearchField {
        let searchField = FixedToolbarSearchField()
        searchField.placeholderString = "搜索"
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: NSFont.systemFontSize)
        searchField.delegate = context.coordinator
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.submit(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: ToolbarMetrics.searchFieldWidth).isActive = true
        searchField.heightAnchor.constraint(equalToConstant: FixedToolbarSearchField.preferredHeight).isActive = true
        return searchField
    }

    /// 同步 SwiftUI 状态到原生搜索框，并刷新回调闭包。
    ///
    /// - Parameters:
    ///   - nsView: 当前托管的原生搜索框。
    ///   - context: SwiftUI 提供的视图上下文。
    func updateNSView(_ nsView: FixedToolbarSearchField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSearch = onSearch

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    /// 创建搜索框协调器，用于把 AppKit 事件桥接回 SwiftUI 状态。
    ///
    /// - Returns: 文本变化和提交事件的协调器。
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSearch: onSearch)
    }

    /// 桥接 `NSSearchField` 文本变化、回车提交和清除按钮事件。
    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var onSearch: (String) -> Void

        /// 保存 SwiftUI 绑定和搜索回调。
        ///
        /// - Parameters:
        ///   - text: 搜索文本绑定。
        ///   - onSearch: 文本变化或提交时调用的搜索函数。
        init(text: Binding<String>, onSearch: @escaping (String) -> Void) {
            self.text = text
            self.onSearch = onSearch
        }

        /// 处理回车提交和搜索框清除按钮触发的搜索动作。
        ///
        /// - Parameter sender: 触发动作的原生搜索框。
        @objc func submit(_ sender: NSSearchField) {
            updateSearch(sender.stringValue)
        }

        /// 处理用户输入过程中的实时文本变化。
        ///
        /// - Parameter notification: AppKit 文本变化通知。
        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            updateSearch(searchField.stringValue)
        }

        /// 同步新搜索词并触发查询。
        ///
        /// - Parameter value: 搜索框中的最新文本。
        private func updateSearch(_ value: String) {
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
            onSearch(value)
        }
    }

    /// 为 SwiftUI toolbar 提供稳定 intrinsic size 的原生搜索控件。
    final class FixedToolbarSearchField: NSSearchField {
        static let preferredHeight: CGFloat = 32

        /// 返回固定尺寸，避免 toolbar 在聚焦状态下把搜索框折叠为图标。
        override var intrinsicContentSize: NSSize {
            NSSize(width: ToolbarMetrics.searchFieldWidth, height: Self.preferredHeight)
        }

        /// 显式处理 Return/Enter，确保用户按回车时也会触发搜索 action。
        ///
        /// - Parameter event: AppKit 传入的键盘事件。
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 76 {
                performSearchAction()
                return
            }
            super.keyDown(with: event)
        }

        /// 将搜索提交转发给当前 target/action。
        ///
        /// `NSSearchField` 在工具栏中有时只发送实时文本变化事件；这里主动发送 action，
        /// 让回车和清除按钮走同一个 coordinator 提交流程。
        func performSearchAction() {
            sendAction(action, to: target)
        }
    }
}
