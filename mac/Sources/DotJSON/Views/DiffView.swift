import SwiftUI
import DotJSONCore

/// 双栏 JSON 对比：结构化 Diff 为主，行级 Diff 为辅。
struct DiffView: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    @Bindable var model: DiffViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(hex: "#333333"))
            if let error = model.errorMessage {
                errorBanner(error)
            } else {
                content
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Color(hex: "#1a1a1a"))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("JSON 对比")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#d4d4d4"))
            if model.hasDirtyFileTargets {
                Text("未保存的文件修改")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#dcdcaa"))
            }
            Spacer()
            Button("保存") {
                workspace.saveActiveDocument()
            }
            .disabled(!model.hasDirtyFileTargets)
            .keyboardShortcut("s", modifiers: .command)
            Button("撤销应用") {
                model.undo(workspace: workspace)
            }
            .disabled(!model.canUndo)
            Button("全部 → 左") {
                model.applyAll(direction: .toLeft, workspace: workspace)
            }
            .disabled(model.comparison?.rows.isEmpty != false)
            Button("全部 → 右") {
                model.applyAll(direction: .toRight, workspace: workspace)
            }
            .disabled(model.comparison?.rows.isEmpty != false)
            Button("关闭") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "#252526"))
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: "#f48771"))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#d4d4d4"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HSplitView {
                sidePane(title: model.left.label, position: .left)
                sidePane(title: model.right.label, position: .right)
            }
            .frame(minHeight: 160, maxHeight: 220)

            structuredSection
                .frame(minHeight: 160)

            lineDiffSection
                .frame(minHeight: 120, maxHeight: 180)
        }
    }

    private func sidePane(title: String, position: DiffSidePosition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sideTitle(title, position: position))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "#858585"))
                Spacer()
                Menu("来源") {
                    if !workspace.tabs.isEmpty {
                        ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { _, tab in
                            Button(tab.documentTitle) {
                                model.useTab(tab, for: position)
                            }
                        }
                        Divider()
                    }
                    Button("打开文件…") { model.pickFile(for: position, workspace: workspace) }
                    Button("剪贴板") { model.useClipboard(for: position, workspace: workspace) }
                }
                .menuStyle(.borderlessButton)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            ScrollView {
                Text(position == .left ? model.left.inlineText : model.right.inlineText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hex: "#cccccc"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(Color(hex: "#1e1e1e"))
        }
    }

    private var structuredSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("路径差异")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#858585"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#252526"))

            if let rows = model.comparison?.rows, !rows.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows, id: \.id) { row in
                            structuredRow(row)
                            Divider().overlay(Color(hex: "#2d2d2d"))
                        }
                    }
                }
            } else {
                Text("无结构化差异")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#858585"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func structuredRow(_ row: JSONDiff.Row) -> some View {
        HStack(spacing: 8) {
            Text(row.kind.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(kindColor(row.kind))
                .frame(width: 56, alignment: .leading)
            Text(row.path.description.isEmpty ? "(root)" : row.path.description)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: "#d4d4d4"))
                .lineLimit(1)
            Spacer()
            Text(summary(row.leftValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(hex: "#858585"))
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
            Text("→")
                .foregroundStyle(Color(hex: "#555555"))
            Text(summary(row.rightValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(hex: "#858585"))
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)
            Button("←") { model.apply(row: row, direction: .toLeft, workspace: workspace) }
                .help("应用到左侧")
            Button("→") { model.apply(row: row, direction: .toRight, workspace: workspace) }
                .help("应用到右侧")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: "#1e1e1e"))
    }

    private var lineDiffSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("行级差异")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#858585"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#252526"))

            Group {
                if let comparison = model.comparison {
                    switch comparison.lineDiff {
                    case .available(let lines):
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                    lineDiffRow(line)
                                }
                            }
                            .padding(8)
                        }
                    case .skipped(let message):
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#858585"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(8)
                    }
                }
            }
            .background(Color(hex: "#1e1e1e"))
        }
    }

    private func lineDiffRow(_ line: JSONDiff.LineRow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.leftLine ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(line.rightLine ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(lineColor(line.kind))
    }

    private func kindColor(_ kind: JSONDiff.Kind) -> Color {
        switch kind {
        case .add: return Color(hex: "#73c991")
        case .remove: return Color(hex: "#f48771")
        case .change: return Color(hex: "#dcdcaa")
        }
    }

    private func lineColor(_ kind: JSONDiff.LineKind) -> Color {
        switch kind {
        case .same: return Color(hex: "#858585")
        case .added: return Color(hex: "#73c991")
        case .removed: return Color(hex: "#f48771")
        case .changed: return Color(hex: "#dcdcaa")
        }
    }

    private func summary(_ node: JSONNode?) -> String {
        guard let node else { return "—" }
        return node.summary
    }

    private func sideTitle(_ title: String, position: DiffSidePosition) -> String {
        let dirty = position == .left ? model.left.isFileDirty : model.right.isFileDirty
        return dirty ? "• \(title)" : title
    }

}
