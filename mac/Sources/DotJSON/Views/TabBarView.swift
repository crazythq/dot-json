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
                        title: tab.documentTitle,
                        filePath: tab.fileURL?.path,
                        isModified: tab.isModified,
                        isActive: index == workspace.activeTabIndex,
                        onActivate: { workspace.activateTab(at: index) },
                        onClose: { workspace.requestCloseTab(at: index) }
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
    let title: String
    let filePath: String?
    let isModified: Bool
    let isActive: Bool
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onActivate) {
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

            // 关闭按钮在 hover 或激活状态时显示
            if isHovering || isActive {
                Button(action: onClose) {
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
    }
}
