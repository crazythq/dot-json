import SwiftUI
import AppKit
import DotJSONCore

private enum ToolbarMetrics {
    static let searchFieldWidth: CGFloat = 140
    static let controlSpacing: CGFloat = 6
    static let symbolPointSize: CGFloat = 14
    static let captionPointSize: CGFloat = 11
    static let verticalIconTitleSpacing: CGFloat = 2
    static let verticalHorizontalPadding: CGFloat = 8
    static let verticalVerticalPadding: CGFloat = 4
    static let verticalButtonMinHeight: CGFloat = 38
    static let iconOnlyPadding: CGFloat = 6
    static let iconOnlyHitSize: CGFloat = 28
    static let actionCornerRadius: CGFloat = 6
    static let menuChevronPointSize: CGFloat = 7
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
            toolbarActionButton("Format", systemImage: "text.alignleft") {
                workspace.activeDocument?.format()
            }
            .help("Format JSON")
        }

        ToolbarItem {
            toolbarActionButton("Minify", systemImage: "text.aligncenter") {
                workspace.activeDocument?.minify()
            }
            .help("Minify JSON")
        }

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
                toolbarMenuActionLabel(
                    String(localized: "toolbar.convert", bundle: .module),
                    systemImage: "arrow.left.arrow.right"
                )
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(ToolbarActionButtonStyle())
            .menuIndicator(.hidden)
            .help(Text("toolbar.convert.help", bundle: .module))
        }

        ToolbarItem {
            toolbarActionButton("Clear", systemImage: "trash") {
                workspace.activeDocument?.clear()
            }
            .help("Clear content")
        }

        ToolbarItem {
            toolbarActionButton("Paste", systemImage: "doc.on.clipboard") {
                pasteFromClipboard()
            }
            .help("Paste and format")
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }

        ToolbarItem {
            toolbarActionButton("Copy", systemImage: "doc.on.doc") {
                copyToClipboard()
            }
            .help("Copy to clipboard")
        }

        // ── 导入/导出 ──
        ToolbarItem {
            toolbarActionButton("Import", systemImage: "square.and.arrow.down") {
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
                toolbarMenuActionLabel("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(ToolbarActionMenuStyle())
            .help("Export JSON")
        }
    }

    private func toolbarActionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarActionLabel(title, systemImage: systemImage)
        }
        .buttonStyle(ToolbarActionButtonStyle())
        .accessibilityLabel(title)
    }

    /// Plain `Button` label — keeps `Label` so overflow `>>` rows retain SF Symbol icons.
    private func toolbarActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(ToolbarActionLabelStyle(showsText: showsToolbarText))
            .contentShape(Rectangle())
            .contextMenu {
                Toggle("Show Text", isOn: $toolbarShowsText)
            }
    }

    /// `Menu` label — custom vertical face; `Menu` would flatten `Label` to horizontal titleAndIcon.
    private func toolbarMenuActionLabel(_ title: String, systemImage: String) -> some View {
        ZStack {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

            ToolbarActionFace(
                title: title,
                systemImage: systemImage,
                showsText: showsToolbarText,
                showsMenuChevron: true
            )
        }
        .contentShape(Rectangle())
        .contextMenu {
            Toggle("Show Text", isOn: $toolbarShowsText)
        }
        .accessibilityLabel(title)
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

/// Shared vertical toolbar face (icon above caption, or padded icon-only).
private struct ToolbarActionFace: View {
    let title: String
    let systemImage: String
    let showsText: Bool
    var showsMenuChevron: Bool = false

    var body: some View {
        Group {
            if showsText {
                VStack(spacing: ToolbarMetrics.verticalIconTitleSpacing) {
                    Image(systemName: systemImage)
                        .font(.system(size: ToolbarMetrics.symbolPointSize))
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack(spacing: 2) {
                        Text(title)
                            .font(.system(size: ToolbarMetrics.captionPointSize))
                            .lineLimit(1)
                        if showsMenuChevron {
                            Image(systemName: "chevron.down")
                                .font(.system(size: ToolbarMetrics.menuChevronPointSize, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, ToolbarMetrics.verticalHorizontalPadding)
                .padding(.vertical, ToolbarMetrics.verticalVerticalPadding)
                .frame(minHeight: ToolbarMetrics.verticalButtonMinHeight)
            } else {
                Image(systemName: systemImage)
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

/// Icon above caption (wide) or padded icon-only (half-fold). Keeps `Label` for overflow `>>` menus.
private struct ToolbarActionLabelStyle: LabelStyle {
    let showsText: Bool

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if showsText {
                VStack(spacing: ToolbarMetrics.verticalIconTitleSpacing) {
                    configuration.icon
                        .font(.system(size: ToolbarMetrics.symbolPointSize))
                        .frame(maxWidth: .infinity, alignment: .center)

                    configuration.title
                        .font(.system(size: ToolbarMetrics.captionPointSize))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, ToolbarMetrics.verticalHorizontalPadding)
                .padding(.vertical, ToolbarMetrics.verticalVerticalPadding)
                .frame(minHeight: ToolbarMetrics.verticalButtonMinHeight)
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

/// Rounded border wraps the full action label (icon + caption rows).
private struct ToolbarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: ToolbarMetrics.actionCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: ToolbarMetrics.actionCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
            }
    }
}

/// Menu actions use the same bordered vertical face as plain toolbar buttons.
private struct ToolbarActionMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .buttonStyle(ToolbarActionButtonStyle())
            .menuIndicator(.hidden)
    }
}
