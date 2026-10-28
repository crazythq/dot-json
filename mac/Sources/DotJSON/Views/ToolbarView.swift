import SwiftUI
import AppKit
import DotJSONCore

private enum ToolbarMetrics {
    static let searchFieldWidth: CGFloat = 140
    static let controlSpacing: CGFloat = 6
    static let iconCanvas: CGFloat = 18
    static let labelColumnWidth: CGFloat = 42
    static let labelHeightWithText: CGFloat = 42
    static let labelHeightIconOnly: CGFloat = 30
    static let transformStrokeWidth: CGFloat = 1.35
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
        // ── Left group ──
        ToolbarItemGroup {
            toolbarJSONTransformButton("Format", kind: .formatted, help: "Format JSON") {
                workspace.activeDocument?.format()
            }

            toolbarJSONTransformButton("Minify", kind: .minified, help: "Minify JSON") {
                workspace.activeDocument?.minify()
            }
        }

        // ── Python / 标准 JSON 互转 ──
        ToolbarItem {
            ControlGroup {
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
            .controlGroupStyle(.navigation)
            .controlSize(.large)
        }

        // ── 文件操作 ──
        ToolbarItem {
            ControlGroup {
                toolbarIconButton("Clear", systemImage: "trash") {
                    workspace.activeDocument?.clear()
                }
                .help("Clear content")

                toolbarIconButton("Paste", systemImage: "doc.on.clipboard") {
                    pasteFromClipboard()
                }
                .help("Paste and format")
                .keyboardShortcut("v", modifiers: [.command, .shift])

                toolbarIconButton("Copy", systemImage: "doc.on.doc") {
                    copyToClipboard()
                }
                .help("Copy to clipboard")
            }
            .controlGroupStyle(.navigation)
            .controlSize(.large)
        }

        // ── 导入/导出 ──
        ToolbarItem {
            ControlGroup {
                toolbarIconButton("Import", systemImage: "square.and.arrow.down") {
                    importDocument()
                }
                .help("Import JSON file")

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
            .controlGroupStyle(.navigation)
            .controlSize(.large)
        }
    }

    private func toolbarJSONTransformButton(
        _ title: String,
        kind: JSONTransformIconShape.Kind,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                jsonTransformIcon(kind: kind)
            }
            .labelStyle(ToolbarIconLabelStyle(showsText: showsToolbarText))
            .contentShape(Rectangle())
            .contextMenu {
                Toggle("Show Text", isOn: $toolbarShowsText)
            }
        }
        .help(help)
        .controlSize(.large)
    }

    private func jsonTransformIcon(kind: JSONTransformIconShape.Kind) -> some View {
        JSONTransformIconShape(kind: kind)
            .stroke(
                style: StrokeStyle(
                    lineWidth: ToolbarMetrics.transformStrokeWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: ToolbarMetrics.iconCanvas, height: ToolbarMetrics.iconCanvas)
            .accessibilityHidden(true)
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
            .labelStyle(ToolbarIconLabelStyle(showsText: showsToolbarText))
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

/// JSON 格式化与压缩操作共用的结构图标。
///
/// 两种状态复用同一对花括号，仅通过内部横线数量表达多行或单行 JSON，
/// 从而让图标在较小的原生工具栏画布中仍保持成对且可辨识。
private struct JSONTransformIconShape: Shape {
    /// 图标所表达的 JSON 输出结构。
    enum Kind {
        case formatted
        case minified
    }

    let kind: Kind

    /// 在给定画布内生成花括号及内容行路径。
    ///
    /// - Parameter rect: SwiftUI 分配给图标的绘制区域。
    /// - Returns: 使用相对坐标构成的矢量路径，可随工具栏尺寸无损缩放。
    func path(in rect: CGRect) -> Path {
        let x = { (value: CGFloat) in rect.minX + rect.width * value }
        let y = { (value: CGFloat) in rect.minY + rect.height * value }
        var path = Path()

        // 花括号轮廓保持完全一致，避免两个操作被误认为无关功能。
        path.move(to: CGPoint(x: x(0.32), y: y(0.06)))
        path.addCurve(
            to: CGPoint(x: x(0.18), y: y(0.33)),
            control1: CGPoint(x: x(0.21), y: y(0.06)),
            control2: CGPoint(x: x(0.24), y: y(0.25))
        )
        path.addCurve(
            to: CGPoint(x: x(0.10), y: y(0.50)),
            control1: CGPoint(x: x(0.18), y: y(0.43)),
            control2: CGPoint(x: x(0.10), y: y(0.42))
        )
        path.addCurve(
            to: CGPoint(x: x(0.18), y: y(0.67)),
            control1: CGPoint(x: x(0.10), y: y(0.58)),
            control2: CGPoint(x: x(0.18), y: y(0.57))
        )
        path.addCurve(
            to: CGPoint(x: x(0.32), y: y(0.94)),
            control1: CGPoint(x: x(0.24), y: y(0.75)),
            control2: CGPoint(x: x(0.21), y: y(0.94))
        )

        path.move(to: CGPoint(x: x(0.68), y: y(0.06)))
        path.addCurve(
            to: CGPoint(x: x(0.82), y: y(0.33)),
            control1: CGPoint(x: x(0.79), y: y(0.06)),
            control2: CGPoint(x: x(0.76), y: y(0.25))
        )
        path.addCurve(
            to: CGPoint(x: x(0.90), y: y(0.50)),
            control1: CGPoint(x: x(0.82), y: y(0.43)),
            control2: CGPoint(x: x(0.90), y: y(0.42))
        )
        path.addCurve(
            to: CGPoint(x: x(0.82), y: y(0.67)),
            control1: CGPoint(x: x(0.90), y: y(0.58)),
            control2: CGPoint(x: x(0.82), y: y(0.57))
        )
        path.addCurve(
            to: CGPoint(x: x(0.68), y: y(0.94)),
            control1: CGPoint(x: x(0.76), y: y(0.75)),
            control2: CGPoint(x: x(0.79), y: y(0.94))
        )

        let rows: [(y: CGFloat, startX: CGFloat, endX: CGFloat)]
        switch kind {
        case .formatted:
            rows = [
                (0.32, 0.38, 0.62),
                (0.50, 0.35, 0.58),
                (0.68, 0.38, 0.65),
            ]
        case .minified:
            rows = [(0.50, 0.35, 0.65)]
        }

        for row in rows {
            path.move(to: CGPoint(x: x(row.startX), y: y(row.y)))
            path.addLine(to: CGPoint(x: x(row.endX), y: y(row.y)))
        }

        return path
    }
}

private struct ToolbarIconLabelStyle: LabelStyle {
    let showsText: Bool

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 2) {
            configuration.icon
                .font(.system(size: 15, weight: .regular))
                .frame(
                    width: ToolbarMetrics.iconCanvas,
                    height: ToolbarMetrics.iconCanvas,
                    alignment: .center
                )

            if showsText {
                configuration.title
                    .font(.system(size: 9, weight: .regular))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .frame(
            width: ToolbarMetrics.labelColumnWidth,
            height: showsText
                ? ToolbarMetrics.labelHeightWithText
                : ToolbarMetrics.labelHeightIconOnly,
            alignment: .center
        )
    }
}
