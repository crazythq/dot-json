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
            toolbarVerticalMenuButton(
                title: String(localized: "toolbar.convert", bundle: .module),
                systemImage: "arrow.left.arrow.right",
                help: String(localized: "toolbar.convert.help", bundle: .module),
                entries: [
                    ToolbarVerticalMenuButton.Entry(
                        title: String(localized: "toolbar.convert.toPython", bundle: .module)
                    ) {
                        workspace.activeDocument?.toPythonLiteral()
                    },
                    ToolbarVerticalMenuButton.Entry(
                        title: String(localized: "toolbar.convert.toJSON", bundle: .module)
                    ) {
                        workspace.activeDocument?.toStandardJSON()
                    },
                ]
            )
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
            toolbarVerticalMenuButton(
                title: "Export",
                systemImage: "square.and.arrow.up",
                help: "Export JSON",
                entries: [
                    ToolbarVerticalMenuButton.Entry(title: "Export Formatted JSON") {
                        export(format: .formatted)
                    },
                    ToolbarVerticalMenuButton.Entry(title: "Export Minified JSON") {
                        export(format: .minified)
                    },
                ]
            )
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

    /// AppKit-hosted vertical menu button — SwiftUI `Menu` ignores custom label chrome in toolbars.
    private func toolbarVerticalMenuButton(
        title: String,
        systemImage: String,
        help: String,
        entries: [ToolbarVerticalMenuButton.Entry]
    ) -> some View {
        ToolbarVerticalMenuButton(
            title: title,
            systemImage: systemImage,
            showsText: showsToolbarText,
            help: help,
            entries: entries,
            toolbarShowsText: $toolbarShowsText
        )
        .help(help)
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

/// Toolbar menu action with a vertical face and AppKit `NSMenu` (no SwiftUI `Menu` label flattening).
struct ToolbarVerticalMenuButton: NSViewRepresentable {
    struct Entry {
        let title: String
        let action: () -> Void

        init(title: String, action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }
    }

    let title: String
    let systemImage: String
    let showsText: Bool
    let help: String
    let entries: [Entry]
    @Binding var toolbarShowsText: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ToolbarVerticalMenuHostView {
        let view = ToolbarVerticalMenuHostView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ToolbarVerticalMenuHostView, context: Context) {
        context.coordinator.entries = entries
        nsView.coordinator = context.coordinator
        nsView.updateLabel(
            ToolbarVerticalMenuButtonLabel(
                title: title,
                systemImage: systemImage,
                showsText: showsText,
                toolbarShowsText: $toolbarShowsText
            )
        )
        nsView.toolTip = help
        nsView.setAccessibilityLabel(title)
        nsView.setAccessibilityHelp(help)
    }

    @MainActor
    final class Coordinator: NSObject {
        var entries: [Entry] = []

        @objc func performMenuAction(_ sender: NSMenuItem) {
            let index = sender.tag
            guard entries.indices.contains(index) else { return }
            entries[index].action()
        }

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            for (index, entry) in entries.enumerated() {
                let item = NSMenuItem(
                    title: entry.title,
                    action: #selector(performMenuAction(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                menu.addItem(item)
            }
            return menu
        }
    }
}

private struct ToolbarVerticalMenuButtonLabel: View {
    let title: String
    let systemImage: String
    let showsText: Bool
    @Binding var toolbarShowsText: Bool

    var body: some View {
        ToolbarActionFace(
            title: title,
            systemImage: systemImage,
            showsText: showsText,
            showsMenuChevron: true
        )
        .toolbarActionChrome()
        .contentShape(Rectangle())
        .contextMenu {
            Toggle("Show Text", isOn: $toolbarShowsText)
        }
    }
}

@MainActor
final class ToolbarVerticalMenuHostView: NSView {
    weak var coordinator: ToolbarVerticalMenuButton.Coordinator?
    private var hostingView: NSHostingView<ToolbarVerticalMenuButtonLabel>?

    override var isFlipped: Bool { true }

    func updateLabel(_ label: ToolbarVerticalMenuButtonLabel) {
        if let hostingView {
            hostingView.rootView = label
            invalidateIntrinsicContentSize()
            return
        }

        let hostingView = NSHostingView(rootView: label)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        self.hostingView = hostingView
    }

    override var intrinsicContentSize: NSSize {
        hostingView?.fittingSize ?? NSSize(width: 44, height: ToolbarMetrics.verticalButtonMinHeight)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown, let coordinator else { return }
        let menu = coordinator.makeMenu()
        let location = NSPoint(x: bounds.midX, y: bounds.minY)
        menu.popUp(positioning: nil, at: location, in: self)
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

private extension View {
    func toolbarActionChrome() -> some View {
        background {
            RoundedRectangle(cornerRadius: ToolbarMetrics.actionCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ToolbarMetrics.actionCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
        }
    }
}

/// Rounded border wraps the full action label (icon + caption rows).
private struct ToolbarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.toolbarActionChrome()
    }
}
