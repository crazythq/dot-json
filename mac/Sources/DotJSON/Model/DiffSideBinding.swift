import Foundation

/// 一侧 JSON 的来源与合并后写回目标。
struct DiffSideBinding: Equatable {
    enum Source: Equatable {
        case tab(UUID)
        case file(URL)
        case clipboard
        case inline
    }

    enum ApplyTarget: Equatable {
        case tab(UUID)
        case file(URL)
        case clipboard
        case inlineOnly
    }

    var source: Source
    var label: String
    var inlineText: String
    /// 最近一次从磁盘加载或成功保存后的内容快照（仅 `ApplyTarget.file` 用于脏标记）。
    var savedSnapshot: String
    var applyTarget: ApplyTarget

    init(
        source: Source,
        label: String,
        inlineText: String,
        applyTarget: ApplyTarget,
        savedSnapshot: String? = nil
    ) {
        self.source = source
        self.label = label
        self.inlineText = inlineText
        self.applyTarget = applyTarget
        self.savedSnapshot = savedSnapshot ?? inlineText
    }

    /// 文件写回目标是否相对磁盘快照有未保存修改。
    var isFileDirty: Bool {
        guard case .file = applyTarget else { return false }
        return inlineText != savedSnapshot
    }

    var fileApplyURL: URL? {
        guard case .file(let url) = applyTarget else { return nil }
        return url
    }

    /// 从文件 URL 构造绑定，默认以磁盘内容为快照。
    static func fromFile(url: URL, text: String) -> DiffSideBinding {
        DiffSideBinding(
            source: .file(url),
            label: url.lastPathComponent,
            inlineText: text,
            applyTarget: .file(url),
            savedSnapshot: text
        )
    }

    /// 将当前 `inlineText` 原子写入文件目标；成功时更新 `savedSnapshot`。
    mutating func persistFileToDiskIfDirty() throws -> Bool {
        guard case .file(let url) = applyTarget, isFileDirty else { return false }
        try inlineText.write(to: url, atomically: true, encoding: .utf8)
        savedSnapshot = inlineText
        return true
    }
}
