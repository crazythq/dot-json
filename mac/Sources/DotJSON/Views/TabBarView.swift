import SwiftUI
import AppKit

/// Xcode 风格的多标签页栏。
///
/// 水平滚动、可关闭、+ 号新建标签页。激活标签页用深色背景突出。
/// 拖拽标签可重排顺序；提交发生在 drop 时，激活态按 tab id 保持稳定（见 `WorkspaceViewModel.moveTab`）。
struct TabBarView: View {
    @Environment(WorkspaceViewModel.self) private var workspace

    /// ~8pt before a press becomes a reorder drag (short click still activates).
    private static let reorderDragMinimumDistance: CGFloat = 8
    /// Vertical cancel when pointer leaves the 32pt bar (global coordinates).
    private static let barHeight: CGFloat = 32
    /// Edge band for horizontal auto-scroll while dragging.
    private static let autoScrollEdgeBand: CGFloat = 24
    private static let autoScrollInterval: TimeInterval = 1.0 / 30.0

    @State private var draggingTabId: UUID?
    @State private var dragExceededThreshold = false
    @State private var insertionIndex: Int?
    @State private var dragCancelled = false
    @State private var dragGlobalLocation: CGPoint = .zero
    @State private var barGlobalFrame: CGRect = .zero
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var suppressTabActivation = false
    @State private var autoScrollDirection: Int = 0

    var body: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(workspace.tabs, id: \.id) { tab in
                            TabBarItemView(
                                tabId: tab.id,
                                title: tab.documentTitle,
                                filePath: tab.fileURL?.path,
                                isModified: tab.isModified,
                                isDragging: draggingTabId == tab.id,
                                dragExceededThreshold: dragExceededThreshold,
                                suppressTabActivation: $suppressTabActivation,
                                onReorderDragChanged: { value in
                                    handleReorderDragChanged(tabId: tab.id, value: value)
                                },
                                onReorderDragEnded: { value in
                                    finishReorderDrag(tabId: tab.id, value: value)
                                }
                            )
                            .id(tab.id)
                        }
                        Button(action: { workspace.newTab() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(hex: "#858585"))
                        .disabled(workspace.tabs.count >= WorkspaceViewModel.maxTabs)
                        .help(
                            workspace.tabs.count >= WorkspaceViewModel.maxTabs
                                ? WorkspaceViewModel.tabLimitAlertMessage
                                : "New Tab"
                        )
                        .padding(.leading, 4)
                    }
                    .padding(.leading, 4)
                }
                .scrollDisabled(draggingTabId != nil)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { barGlobalFrame = geometry.frame(in: .global) }
                            .onChange(of: geometry.frame(in: .global)) { _, frame in
                                barGlobalFrame = frame
                            }
                    }
                )

                if let lineX = insertionLineGlobalX, draggingTabId != nil, !dragCancelled {
                    Rectangle()
                        .fill(Color(hex: "#007acc"))
                        .frame(width: 2, height: 20)
                        .position(x: lineX - barGlobalFrame.minX, y: Self.barHeight / 2)
                }
            }
            .onPreferenceChange(TabBarItemFrameKey.self) { tabFrames = $0 }
            .onChange(of: dragGlobalLocation) { _, _ in
                updateAutoScroll()
            }
            .onChange(of: draggingTabId) { _, id in
                if id == nil {
                    stopAutoScroll()
                }
            }
            .onReceive(
                Timer.publish(every: Self.autoScrollInterval, on: .main, in: .common).autoconnect()
            ) { _ in
                guard autoScrollDirection != 0,
                      draggingTabId != nil,
                      !dragCancelled else { return }
                performAutoScrollStep(direction: autoScrollDirection, scrollProxy: scrollProxy)
            }
        }
        .frame(height: Self.barHeight)
        .background(Color(hex: "#1a1a1a"))
    }

    private var insertionLineGlobalX: CGFloat? {
        guard let insertionIndex else { return nil }
        let ordered = workspace.tabs.map(\.id)
        guard !ordered.isEmpty else { return nil }

        if insertionIndex == 0, let first = ordered.first, let frame = tabFrames[first] {
            return frame.minX
        }
        if insertionIndex >= ordered.count, let last = ordered.last, let frame = tabFrames[last] {
            return frame.maxX
        }
        guard ordered.indices.contains(insertionIndex),
              let frame = tabFrames[ordered[insertionIndex]] else { return nil }
        return frame.minX
    }

    private func handleReorderDragChanged(tabId: UUID, value: DragGesture.Value) {
        if draggingTabId == nil {
            draggingTabId = tabId
            dragExceededThreshold = false
            dragCancelled = false
            insertionIndex = nil
        }
        guard draggingTabId == tabId else { return }

        let distance = hypot(value.translation.width, value.translation.height)
        if distance >= Self.reorderDragMinimumDistance {
            dragExceededThreshold = true
        }

        if let frame = tabFrames[tabId] {
            dragGlobalLocation = CGPoint(
                x: frame.minX + value.location.x,
                y: frame.minY + value.location.y
            )
        }

        if !barGlobalFrame.contains(dragGlobalLocation) {
            dragCancelled = true
            insertionIndex = nil
            stopAutoScroll()
            return
        }

        dragCancelled = false
        insertionIndex = insertionIndex(forGlobalX: dragGlobalLocation.x)
    }

    private func finishReorderDrag(tabId: UUID, value: DragGesture.Value) {
        defer {
            if dragExceededThreshold {
                suppressTabActivation = true
                DispatchQueue.main.async {
                    suppressTabActivation = false
                }
            }
            draggingTabId = nil
            dragExceededThreshold = false
            insertionIndex = nil
            dragCancelled = false
            stopAutoScroll()
        }

        guard draggingTabId == tabId, dragExceededThreshold, !dragCancelled,
              let targetIndex = insertionIndex,
              let sourceIndex = workspace.tabs.firstIndex(where: { $0.id == tabId }) else { return }

        workspace.moveTab(from: sourceIndex, to: targetIndex)
        _ = value
    }

    /// Maps horizontal position to “insert before index” (0…tabCount).
    private func insertionIndex(forGlobalX x: CGFloat) -> Int {
        let orderedIDs = workspace.tabs.map(\.id)
        for (index, id) in orderedIDs.enumerated() {
            guard let frame = tabFrames[id] else { continue }
            if x < frame.midX {
                return index
            }
        }
        return orderedIDs.count
    }

    private func updateAutoScroll() {
        guard draggingTabId != nil, !dragCancelled, !barGlobalFrame.isEmpty else {
            stopAutoScroll()
            return
        }

        let x = dragGlobalLocation.x
        let leftEdge = barGlobalFrame.minX + Self.autoScrollEdgeBand
        let rightEdge = barGlobalFrame.maxX - Self.autoScrollEdgeBand

        if x < leftEdge {
            autoScrollDirection = -1
        } else if x > rightEdge {
            autoScrollDirection = 1
        } else {
            stopAutoScroll()
        }
    }

    @MainActor
    private func performAutoScrollStep(direction: Int, scrollProxy: ScrollViewProxy) {
        guard let draggingTabId,
              let currentIndex = workspace.tabs.firstIndex(where: { $0.id == draggingTabId }) else { return }

        let neighbor = currentIndex + direction
        guard workspace.tabs.indices.contains(neighbor) else { return }
        let neighborId = workspace.tabs[neighbor].id
        withAnimation(.linear(duration: Self.autoScrollInterval)) {
            scrollProxy.scrollTo(neighborId, anchor: direction < 0 ? .leading : .trailing)
        }
        insertionIndex = insertionIndex(forGlobalX: dragGlobalLocation.x)
    }

    private func stopAutoScroll() {
        autoScrollDirection = 0
    }
}

private struct TabBarItemFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// 单个标签页项。
private struct TabBarItemView: View {
    @Environment(WorkspaceViewModel.self) private var workspace

    let tabId: UUID
    let title: String
    let filePath: String?
    let isModified: Bool
    let isDragging: Bool
    let dragExceededThreshold: Bool
    @Binding var suppressTabActivation: Bool
    let onReorderDragChanged: (DragGesture.Value) -> Void
    let onReorderDragEnded: (DragGesture.Value) -> Void

    @State private var isHovering = false
    @State private var isEditingTitle = false
    @State private var editingTitle = ""
    @FocusState private var titleFieldFocused: Bool

    private var tabIndex: Int? {
        workspace.tabs.firstIndex(where: { $0.id == tabId })
    }

    private var isActive: Bool {
        guard let tabIndex else { return false }
        return tabIndex == workspace.activeTabIndex
    }

    var body: some View {
        HStack(spacing: 4) {
            if isEditingTitle {
                TextField("Name", text: $editingTitle)
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
                titleLabel
                    .help(filePath ?? title)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !suppressTabActivation, !dragExceededThreshold else { return }
                        activateTabIfPossible()
                    }
                    .highPriorityGesture(
                        TapGesture(count: 2).onEnded {
                            guard !isDragging else { return }
                            beginRename()
                        }
                    )
                    .gesture(reorderDragGesture, including: isEditingTitle ? .none : .all)
            }

            if isHovering || isActive {
                Button(action: { closeTabIfPossible() }) {
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
        .scaleEffect(isDragging ? 1.03 : 1)
        .shadow(color: isDragging ? Color.black.opacity(0.35) : .clear, radius: 4, y: 2)
        .offset(y: isDragging ? -1 : 0)
        .zIndex(isDragging ? 1 : 0)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TabBarItemFrameKey.self,
                    value: [tabId: geometry.frame(in: .global)]
                )
            }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            contextMenuContent
        }
    }

    private var titleLabel: some View {
        HStack(spacing: 4) {
            Text(isModified ? "• \(title)" : title)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 140)
    }

    private var reorderDragGesture: some Gesture {
        DragGesture(minimumDistance: TabBarView.reorderDragMinimumDistanceForItem)
            .onChanged(onReorderDragChanged)
            .onEnded(onReorderDragEnded)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            closeTabIfPossible()
        } label: {
            Text("tab.context.closeCurrent", bundle: .module)
        }
        Button {
            if let tabIndex { workspace.closeOtherTabs(at: tabIndex) }
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
            if let tabIndex { workspace.duplicateTab(at: tabIndex) }
        } label: {
            Text("tab.context.duplicate", bundle: .module)
        }
        Divider()
        Button {
            guard let tabIndex else { return }
            let focused = workspace.activeTabIndex
            workspace.presentDiff(focusedTabIndex: focused, otherTabIndex: tabIndex)
        } label: {
            Text("tab.context.compare", bundle: .module)
        }
        .disabled({
            guard let tabIndex else { return true }
            return workspace.activeTabIndex < 0 || tabIndex == workspace.activeTabIndex
        }())
    }

    private func activateTabIfPossible() {
        guard let tabIndex else { return }
        workspace.activateTab(at: tabIndex)
    }

    private func closeTabIfPossible() {
        guard let tabIndex else { return }
        workspace.requestCloseTab(at: tabIndex)
    }

    private func beginRename() {
        guard !isEditingTitle else { return }
        editingTitle = title
        isEditingTitle = true
    }

    private func commitRename() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != title, let tabIndex {
            workspace.renameTab(at: tabIndex, to: trimmed)
        }
        isEditingTitle = false
    }

    private func cancelRename() {
        editingTitle = title
        isEditingTitle = false
    }
}

private extension TabBarView {
    /// Exposed for `TabBarItemView` drag gesture (same threshold as bar-level constant).
    static var reorderDragMinimumDistanceForItem: CGFloat { reorderDragMinimumDistance }
}
