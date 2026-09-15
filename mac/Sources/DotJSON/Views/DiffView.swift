import SwiftUI
import DotJSONCore

/// 双栏 JSON 对比：结构化 Diff 为主，行级 Diff 为辅。
struct DiffView: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    @Bindable var model: DiffViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(hex: "#333333"))
            if let error = model.errorMessage {
                operationErrorBanner(error)
            }
            content
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Color(hex: "#1a1a1a"))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("JSON Diff")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#d4d4d4"))
            if model.hasDirtyFileTargets {
                Text("Unsaved file changes")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#dcdcaa"))
            }
            Spacer()
            Button("Save") {
                do {
                    try model.saveDirtyFileTargets(workspace: workspace)
                } catch {
                    model.reportError(error)
                }
            }
            .disabled(!model.hasDirtyFileTargets)
            .keyboardShortcut("s", modifiers: .command)
            Button("Undo Apply") {
                model.undo(workspace: workspace)
            }
            .disabled(!model.canUndo)
            Button("Apply all: Left ← Right") {
                model.applyAll(direction: .toLeft, workspace: workspace)
            }
            .disabled(model.comparison?.rows.isEmpty != false)
            Button("Apply all: Left → Right") {
                model.applyAll(direction: .toRight, workspace: workspace)
            }
            .disabled(model.comparison?.rows.isEmpty != false)
            Button("Close") { workspace.requestDismissDiff() }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "#252526"))
    }

    private func operationErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: "#f48771"))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#d4d4d4"))
                .lineLimit(2)
            Spacer()
            Button("Dismiss") { model.clearOperationError() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#4fc1ff"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "#3a2d2d"))
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
                Menu("Source") {
                    if !workspace.tabs.isEmpty {
                        ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { _, tab in
                            Button(tab.documentTitle) {
                                model.useTab(tab, for: position)
                            }
                        }
                        Divider()
                    }
                    Button("Open File…") { model.pickFile(for: position, workspace: workspace) }
                    Button("Clipboard") { model.useClipboard(for: position, workspace: workspace) }
                }
                .menuStyle(.borderlessButton)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            sideTextEditor(position: position)
                .background(Color(hex: "#1e1e1e"))

            if let parseError = sideParseError(position) {
                Text(parseError)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "#f48771"))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
    }

    private func sideTextEditor(position: DiffSidePosition) -> some View {
        TextEditor(text: sideTextBinding(position))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(hex: "#cccccc"))
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sideTextBinding(_ position: DiffSidePosition) -> Binding<String> {
        Binding(
            get: {
                switch position {
                case .left: model.left.inlineText
                case .right: model.right.inlineText
                }
            },
            set: { newValue in
                model.setInlineText(newValue, on: position, workspace: workspace)
            }
        )
    }

    private func sideParseError(_ position: DiffSidePosition) -> String? {
        switch position {
        case .left: model.leftParseError
        case .right: model.rightParseError
        }
    }

    private var structuredSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Path Diff")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#858585"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#252526"))

            if model.leftParseError != nil || model.rightParseError != nil {
                structuredParseErrorPlaceholder
            } else if let rows = model.comparison?.rows, !rows.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows, id: \.id) { row in
                            structuredRow(row)
                            Divider().overlay(Color(hex: "#2d2d2d"))
                        }
                    }
                }
            } else if model.comparison != nil {
                Text("No structural differences")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#858585"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Enter valid JSON on both sides to compare")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#858585"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func structuredRow(_ row: JSONDiff.Row) -> some View {
        HStack(spacing: 8) {
            Text(kindLetter(row.kind))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(kindColor(row.kind))
                .frame(width: 16, alignment: .leading)
            Text(row.path.description.isEmpty ? "(root)" : row.path.description)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: "#d4d4d4"))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(summary(row.leftValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(hex: "#858585"))
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
            Button("<<") { model.apply(row: row, direction: .toLeft, workspace: workspace) }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#4fc1ff"))
                .buttonStyle(.plain)
                .help("<< Right into Left")
            Button(">>") { model.apply(row: row, direction: .toRight, workspace: workspace) }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#4fc1ff"))
                .buttonStyle(.plain)
                .help(">> Left into Right")
            Text(summary(row.rightValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(hex: "#858585"))
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: "#1e1e1e"))
    }

    private func kindLetter(_ kind: JSONDiff.Kind) -> String {
        switch kind {
        case .add: return "A"
        case .remove: return "D"
        case .change: return "M"
        }
    }

    private var lineDiffSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Line Diff")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#858585"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#252526"))

            Group {
                if model.leftParseError != nil || model.rightParseError != nil {
                    Text("Line diff unavailable until both sides parse as JSON")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#858585"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
                } else if let comparison = model.comparison {
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
                } else {
                    Text("Line diff unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#858585"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
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
        let side = position == .left ? model.left : model.right
        return side.showsUnsavedIndicator ? "• \(title)" : title
    }

    private var structuredParseErrorPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Path diff unavailable")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "#d4d4d4"))
            if let message = model.leftParseError {
                Text("Left: \(message)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#f48771"))
            }
            if let message = model.rightParseError {
                Text("Right: \(message)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#f48771"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

}
