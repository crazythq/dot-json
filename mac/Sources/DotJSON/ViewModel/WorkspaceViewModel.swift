import Foundation
import AppKit
import Observation
import DotJSONCore

/// 管理多标签页、激活文档、最近文件和会话持久化。
@MainActor
@Observable
final class WorkspaceViewModel {

    private enum Key {
        static let workspaceState = "dotjson.workspaceState"
    }

    private struct SessionSnapshot: Codable {
        let fileURLs: [String]
        let activeIndex: Int
        let recentFiles: [String]
    }

    nonisolated(unsafe) static weak var shared: WorkspaceViewModel?

    private(set) var tabs: [EditorViewModel] = []
    var activeTabIndex: Int = -1
    var recentFiles: [URL] = []
    private var isRestoringSession = true

    var activeDocument: EditorViewModel? {
        guard tabs.indices.contains(activeTabIndex) else { return nil }
        return tabs[activeTabIndex]
    }

    var activeErrorLineNumber: Int { activeDocument?.errorLineNumber ?? 0 }
    var activeErrorMessage: String? { activeDocument?.errorMessage }

    init() {
        Self.shared = self
        restoreSession()
    }

    // MARK: - Tab Management

    func newTab() {
        let vm = EditorViewModel()
        tabs.append(vm)
        activeTabIndex = tabs.count - 1
        persistSession()
    }

    func openTab(from url: URL) throws {
        if let existingIndex = tabs.firstIndex(where: { $0.fileURL == url }) {
            activeTabIndex = existingIndex
            return
        }

        let vm = EditorViewModel()
        try vm.loadDocument(from: url)
        tabs.append(vm)
        activeTabIndex = tabs.count - 1
        addRecent(url)
        persistSession()
    }

    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].cancelBackgroundTasks()
        tabs.remove(at: index)
        if tabs.isEmpty {
            activeTabIndex = -1
        } else if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        } else if activeTabIndex > index {
            activeTabIndex -= 1
        }
        persistSession()
    }

    func activateTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabIndex = index
        persistSession()
    }

    // MARK: - Document Operations

    func openDocument(from url: URL) {
        if let existingIndex = tabs.firstIndex(where: { $0.fileURL == url }) {
            activeTabIndex = existingIndex
            return
        }

        if tabs.count == 1, tabs[0].fileURL == nil, !tabs[0].isModified {
            do {
                let vm = tabs[0]
                try vm.loadDocument(from: url)
                addRecent(url)
                persistSession()
                return
            } catch {
                tabs[0].reportFileError(error)
                return
            }
        }

        do {
            try openTab(from: url)
        } catch {
            if let active = activeDocument {
                active.reportFileError(error)
            }
        }
    }

    func saveActiveDocument() {
        guard let doc = activeDocument else { return }
        if let url = doc.fileURL {
            do {
                try doc.save(to: url)
                persistSession()
            } catch {
                doc.reportFileError(error)
            }
        }
    }

    func saveActiveDocumentAs() {
        guard let doc = activeDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let title = doc.documentTitle
        panel.nameFieldStringValue = title.lowercased().hasSuffix(".json")
            ? title
            : "\(title).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try doc.save(to: url)
                self.addRecent(url)
                self.persistSession()
            } catch {
                doc.reportFileError(error)
            }
        }
    }

    // MARK: - Recent Files

    func addRecent(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 10 { recentFiles = Array(recentFiles.prefix(10)) }
        persistSession()
    }

    func clearRecentFiles() {
        recentFiles = []
        persistSession()
    }

    // MARK: - Persistence

    /// 持久化当前会话到 UserDefaults。
    func persistSession() {
        guard !isRestoringSession else { return }
        let snapshot = SessionSnapshot(
            fileURLs: tabs.map { $0.fileURL?.path ?? "" },
            activeIndex: activeTabIndex,
            recentFiles: recentFiles.map { $0.path }
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Key.workspaceState)
        }
    }

    /// 从 UserDefaults 恢复上次会话。
    private func restoreSession() {
        defer { isRestoringSession = false }

        guard let data = UserDefaults.standard.data(forKey: Key.workspaceState),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data) else {
            newTab()
            return
        }

        recentFiles = snapshot.recentFiles.compactMap { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        let urls = snapshot.fileURLs.map { URL(fileURLWithPath: $0) }
            .filter { !$0.path.isEmpty && FileManager.default.fileExists(atPath: $0.path) }

        if urls.isEmpty {
            newTab()
            return
        }

        for url in urls {
            let vm = EditorViewModel()
            do {
                try vm.loadDocument(from: url)
                tabs.append(vm)
            } catch {
                // 文件已被删除或不可读，跳过。
            }
        }

        if tabs.isEmpty {
            newTab()
        } else {
            activeTabIndex = min(max(snapshot.activeIndex, 0), tabs.count - 1)
        }
    }
}
