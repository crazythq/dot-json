import SwiftUI
import AppKit
import DotJSONCore

private enum ToolbarMetrics {
    static let searchFieldWidth: CGFloat = 140
    static let controlSpacing: CGFloat = 6
}

struct ToolbarView: ToolbarContent {
    @Environment(WorkspaceViewModel.self) private var workspace
    @AppStorage("toolbarShowsText") private var toolbarShowsText: Bool = true

    var body: some ToolbarContent {
        // ── Left group ──
        ToolbarItemGroup {
            Button(action: { workspace.activeDocument?.format() }) {
                Label("格式化", systemImage: "text.alignleft")
            }
            .help("格式化 JSON")

            Button(action: { workspace.activeDocument?.minify() }) {
                Label("压缩", systemImage: "text.aligncenter")
            }
            .help("压缩 JSON")

            if let doc = workspace.activeDocument {
                Picker("缩进", selection: Bindable(doc).indent) {
                    ForEach(JSONFormatter.Indent.allCases, id: \.self) { o in
                        Text(o.label).tag(o)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .help("缩进：2 空格 / 4 空格 / Tab")
            }
        }

        // ── 文件操作 ──
        ToolbarItem {
            ControlGroup {
                toolbarIconButton("清空", systemImage: "trash") {
                    workspace.activeDocument?.clear()
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
    }

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
        workspace.activeDocument?.pasteAndFormat(text)
    }

    private func copyToClipboard() {
        guard let doc = workspace.activeDocument else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(doc.rawText, forType: .string)
    }

    private func importDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let ws = WorkspaceViewModel.shared else { return }
            ws.openDocument(from: url)
        }
    }

    private func export(format: EditorViewModel.ExportFormat) {
        guard let doc = workspace.activeDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let title = doc.documentTitle
        panel.nameFieldStringValue = title.lowercased().hasSuffix(".json")
            ? title
            : "\(title).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try doc.export(to: url, format: format)
            } catch {
                doc.reportFileError(error)
            }
        }
    }
}

private struct ToolbarIconLabelStyle: LabelStyle {
    let showsText: Bool

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
