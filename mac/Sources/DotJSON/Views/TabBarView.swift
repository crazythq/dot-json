import SwiftUI
import AppKit

/// Xcode 风格的多标签页栏。
///
/// 水平滚动、可关闭、+ 号新建标签页。激活标签页用深色背景突出。
struct TabBarView: View {
    @Environment(WorkspaceViewModel.self) private var workspace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                    TabBarItemView(
                        index: index,
                        title: tab.documentTitle,
                        filePath: tab.fileURL?.path,
                        isModified: tab.isModified
                    )
                }
                // 新建标签页按钮
                Button(action: { workspace.newTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(hex: "#858585"))
                .help("新建标签页")
                .padding(.leading, 4)
            }
            .padding(.leading, 4)
        }
        .frame(height: 32)
        .background(Color(hex: "#1a1a1a"))
    }
}

/// 单个标签页项。
private struct TabBarItemView: View {
    @Environment(WorkspaceViewModel.self) private var workspace

    let index: Int
    let title: String
    let filePath: String?
    let isModified: Bool

    @State private var isHovering = false
    @State private var isEditingTitle = false
    @State private var editingTitle = ""
    @FocusState private var titleFieldFocused: Bool

    private var isActive: Bool { index == workspace.activeTabIndex }

    var body: some View {
        HStack(spacing: 4) {
            if isEditingTitle {
                TextField("命名", text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#ffffff"))
                    .focused($titleFieldFocused)
                    .frame(maxWidth: 140)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "#2d2d2d"))
                    )
                    .onAppear { titleFieldFocused = true }
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .onChange(of: titleFieldFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Button(action: { workspace.activateTab(at: index) }) {
                    HStack(spacing: 4) {
                        Text(isModified ? "• \(title)" : title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: 140)
                }
                .buttonStyle(.plain)
                .help(filePath ?? title)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { beginRename() }
                )
            }

            // 关闭按钮在 hover 或激活状态时显示
            if isHovering || isActive {
                Button(action: { workspace.requestCloseTab(at: index) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(hex: "#858585"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color(hex: "#252526") : Color.clear)
        )
        .foregroundColor(isActive ? Color(hex: "#ffffff") : Color(hex: "#858585"))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button {
                workspace.requestCloseTab(at: index)
            } label: {
                Text("tab.context.closeCurrent", bundle: .module)
            }
            Button {
                workspace.closeOtherTabs(at: index)
            } label: {
                Text("tab.context.closeOthers", bundle: .module)
            }
            Button {
                workspace.closeAllTabs()
            } label: {
                Text("tab.context.closeAll", bundle: .module)
            }
            Divider()
            Button {
                beginRename()
            } label: {
                Text("tab.context.rename", bundle: .module)
            }
            Button {
                workspace.duplicateTab(at: index)
            } label: {
                Text("tab.context.duplicate", bundle: .module)
            }
            Divider()
            Button {
                let focused = workspace.activeTabIndex
                workspace.presentDiff(focusedTabIndex: focused, otherTabIndex: index)
            } label: {
                Text("tab.context.compare", bundle: .module)
            }
            .disabled(workspace.activeTabIndex < 0 || index == workspace.activeTabIndex)
        }
    }

    /// 双击进入重命名模式，预填当前标题。
    private func beginRename() {
        guard !isEditingTitle else { return }
        editingTitle = title
        isEditingTitle = true
    }

    /// 提交重命名（回车或失焦时触发）；标题未变化或为空时不写入。
    private func commitRename() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != title {
            workspace.renameTab(at: index, to: trimmed)
        }
        isEditingTitle = false
    }

    /// 取消重命名（Esc）：恢复原标题后退出编辑。
    private func cancelRename() {
        editingTitle = title
        isEditingTitle = false
    }
}
