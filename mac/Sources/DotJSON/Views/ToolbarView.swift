import SwiftUI
import AppKit
import DotJSONCore

private enum ToolbarMetrics {
    static let searchFieldWidth: CGFloat = 140
    static let controlSpacing: CGFloat = 6
    static let symbolPointSize: CGFloat = 14
    static let titleAndIconHorizontalPadding: CGFloat = 8
    static let titleAndIconVerticalPadding: CGFloat = 4
    static let titleAndIconSpacing: CGFloat = 5
    static let iconOnlyPadding: CGFloat = 6
    static let iconOnlyHitSize: CGFloat = 28
    /// Below this content width, hide icon captions before relying on toolbar overflow.
    static let hideTextBelowWidth: CGFloat = 780
}

struct ToolbarView: ToolbarContent {
    /// Main editor width; used to hide captions on narrow windows before toolbar overflow.
    var windowWidth: CGFloat = .greatestFiniteMagnitude

    @Environment(WorkspaceViewModel.self) private var workspace
    @AppStorage("toolbarShowsText") private var toolbarShowsText: Bool = true

    private var showsToolbarText: Bool {
        toolbarShowsText && windowWidth >= ToolbarMetrics.hideTextBelowWidth
    }

    var body: some ToolbarContent {
        ToolbarItem {
            toolbarIconButton("Format", systemImage: "text.alignleft") {
                workspace.activeDocument?.format()
            }
            .help("Format JSON")
        }

        ToolbarItem {
            toolbarIconButton("Minify", systemImage: "text.aligncenter") {
                workspace.activeDocument?.minify()
            }
            .help("Minify JSON")
        }

        // ── Python / 标准 JSON 互转 ──
        ToolbarItem {
            Menu {
                Button {
                    workspace.activeDocument?.toPythonLiteral()
                } label: {
                    Text("toolbar.convert.toPython", bundle: .module)
                }
                Button {
                    workspace.activeDocument?.toStandardJSON()
                } label: {
                    Text("toolbar.convert.toJSON", bundle: .module)
                }
            } label: {
                toolbarIconLabel(
                    String(localized: "toolbar.convert", bundle: .module),
                    systemImage: "arrow.left.arrow.right"
                )
            }
            .help(Text("toolbar.convert.help", bundle: .module))
        }

        // ── 文件操作 ──
        ToolbarItem {
            toolbarIconButton("Clear", systemImage: "trash") {
                workspace.activeDocument?.clear()
            }
            .help("Clear content")
        }

        ToolbarItem {
            toolbarIconButton("Paste", systemImage: "doc.on.clipboard") {
                pasteFromClipboard()
            }
            .help("Paste and format")
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }

        ToolbarItem {
            toolbarIconButton("Copy", systemImage: "doc.on.doc") {
                copyToClipboard()
            }
            .help("Copy to clipboard")
        }

        // ── 导入/导出 ──
        ToolbarItem {
            toolbarIconButton("Import", systemImage: "square.and.arrow.down") {
                importDocument()
            }
            .help("Import JSON file")
        }

        ToolbarItem {
            Menu {
                Button("Export Formatted JSON") {
                    export(format: .formatted)
                }
                Button("Export Minified JSON") {
                    export(format: .minified)
                }
            } label: {
                toolbarIconLabel("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export JSON")
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
        .accessibilityLabel(title)
    }

    private func toolbarIconLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(ToolbarAdaptiveLabelStyle(showsText: showsToolbarText))
            .contentShape(Rectangle())
            .contextMenu {
                Toggle("Show Text", isOn: $toolbarShowsText)
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
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK, let ws = WorkspaceViewModel.shared else { return }
            ws.openDocuments(panel.urls)
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

/// Horizontal icon+title or padded icon-only layout so toolbar and overflow menus keep SF Symbol icons.
private struct ToolbarAdaptiveLabelStyle: LabelStyle {
    let showsText: Bool

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if showsText {
                HStack(spacing: ToolbarMetrics.titleAndIconSpacing) {
                    configuration.icon
                        .font(.system(size: ToolbarMetrics.symbolPointSize))
                    configuration.title
                        .font(.system(size: ToolbarMetrics.symbolPointSize))
                }
                .padding(.horizontal, ToolbarMetrics.titleAndIconHorizontalPadding)
                .padding(.vertical, ToolbarMetrics.titleAndIconVerticalPadding)
            } else {
                configuration.icon
                    .font(.system(size: ToolbarMetrics.symbolPointSize))
                    .padding(ToolbarMetrics.iconOnlyPadding)
                    .frame(
                        width: ToolbarMetrics.iconOnlyHitSize,
                        height: ToolbarMetrics.iconOnlyHitSize
                    )
            }
        }
        .foregroundStyle(.primary)
    }
}
