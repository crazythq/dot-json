import Foundation
import UniformTypeIdentifiers

/// Extensions we manage as default openers.
enum ManagedJSONExtension: String, CaseIterable, Codable, Sendable {
    case json
    case jsonl

    var filenameExtension: String { rawValue }

    var preferredContentType: UTType {
        switch self {
        case .json:
            return .json
        case .jsonl:
            if let exported = UTType("sh.crazy.dotjson.jsonl") {
                return exported
            }
            if let imported = UTType("org.jsonlines.jsonl") {
                return imported
            }
            return UTType(filenameExtension: "jsonl") ?? .plainText
        }
    }
}

/// Prior default handler URLs persisted before DotJSON became default.
struct PriorHandlerSnapshot: Equatable, Sendable {
    var jsonAppURL: URL?
    var jsonlAppURL: URL?

    func url(for ext: ManagedJSONExtension) -> URL? {
        switch ext {
        case .json: jsonAppURL
        case .jsonl: jsonlAppURL
        }
    }

    mutating func set(_ url: URL?, for ext: ManagedJSONExtension) {
        switch ext {
        case .json: jsonAppURL = url
        case .jsonl: jsonlAppURL = url
        }
    }
}

/// Derived toggle state from live system defaults (both extensions must point at self).
struct FileAssociationToggleState: Equatable, Sendable {
    let isDotJSONDefaultForJSON: Bool
    let isDotJSONDefaultForJSONL: Bool

    var isFullyOn: Bool { isDotJSONDefaultForJSON && isDotJSONDefaultForJSONL }
}

enum FileAssociationLogic {
    /// Whether the running app bundle is the default opener for an extension.
    static func isSelfDefault(
        defaultApp: URL?,
        selfAppURL: URL
    ) -> Bool {
        guard let defaultApp else { return false }
        return defaultApp.standardizedFileURL == selfAppURL.standardizedFileURL
    }

    static func toggleState(
        jsonDefault: URL?,
        jsonlDefault: URL?,
        selfAppURL: URL
    ) -> FileAssociationToggleState {
        FileAssociationToggleState(
            isDotJSONDefaultForJSON: isSelfDefault(defaultApp: jsonDefault, selfAppURL: selfAppURL),
            isDotJSONDefaultForJSONL: isSelfDefault(defaultApp: jsonlDefault, selfAppURL: selfAppURL)
        )
    }

    /// When enabling, snapshot current handlers into prior unless DotJSON is already default for both
    /// (do not overwrite stored prior in that case).
    static func shouldPersistPriorWhenEnabling(state: FileAssociationToggleState) -> Bool {
        !state.isFullyOn
    }

    /// Prior values to write before changing defaults (current system handlers).
    static func priorToPersistWhenEnabling(
        jsonDefault: URL?,
        jsonlDefault: URL?,
        selfAppURL: URL
    ) -> PriorHandlerSnapshot {
        var snapshot = PriorHandlerSnapshot()
        if !isSelfDefault(defaultApp: jsonDefault, selfAppURL: selfAppURL) {
            snapshot.jsonAppURL = jsonDefault
        }
        if !isSelfDefault(defaultApp: jsonlDefault, selfAppURL: selfAppURL) {
            snapshot.jsonlAppURL = jsonlDefault
        }
        return snapshot
    }

    /// Order for applying defaults when turning on.
    static let enableOrder: [ManagedJSONExtension] = [.json, .jsonl]

    /// Extensions already using DotJSON before this enable attempt (must not roll back on failure).
    static func extensionsAlreadySelf(
        jsonDefault: URL?,
        jsonlDefault: URL?,
        selfAppURL: URL
    ) -> Set<ManagedJSONExtension> {
        var already = Set<ManagedJSONExtension>()
        if isSelfDefault(defaultApp: jsonDefault, selfAppURL: selfAppURL) {
            already.insert(.json)
        }
        if isSelfDefault(defaultApp: jsonlDefault, selfAppURL: selfAppURL) {
            already.insert(.jsonl)
        }
        return already
    }

    /// After a partial enable failure, roll back only extensions changed non-self → DotJSON (reverse order).
    static func rollbackTargetsAfterPartialEnable(
        changedToSelf: [ManagedJSONExtension],
        prior: PriorHandlerSnapshot
    ) -> [(ManagedJSONExtension, URL?)] {
        changedToSelf.reversed().map { ext in
            (ext, prior.url(for: ext))
        }
    }

    static func extensionsStillUsingSelf(
        jsonDefault: URL?,
        jsonlDefault: URL?,
        selfAppURL: URL
    ) -> [ManagedJSONExtension] {
        ManagedJSONExtension.allCases.filter { ext in
            let defaultApp = ext == .json ? jsonDefault : jsonlDefault
            return isSelfDefault(defaultApp: defaultApp, selfAppURL: selfAppURL)
        }
    }

    /// Restore plan when turning off: each extension uses stored prior if the app still exists.
    enum RestoreAction: Equatable, Sendable {
        case restorePrior(URL)
        case resetToSystemFallback
    }

    static func restoreAction(
        for ext: ManagedJSONExtension,
        prior: PriorHandlerSnapshot?,
        priorAppExists: (URL) -> Bool
    ) -> RestoreAction {
        guard let priorURL = prior?.url(for: ext) else {
            return .resetToSystemFallback
        }
        if priorAppExists(priorURL) {
            return .restorePrior(priorURL)
        }
        return .resetToSystemFallback
    }

    /// Pick a non-self system app for “Reset to macOS default”.
    /// Prefer `urlForApplication` when it is not DotJSON; otherwise TextEdit on a typical install.
    static func systemFallbackApp(
        for ext: ManagedJSONExtension,
        workspaceCandidate: URL?,
        selfAppURL: URL
    ) -> URL? {
        if let workspaceCandidate,
           workspaceCandidate.standardizedFileURL != selfAppURL.standardizedFileURL {
            return workspaceCandidate
        }
        let bundledFallbacks = [
            "/System/Applications/TextEdit.app",
            "/Applications/TextEdit.app",
        ]
        for path in bundledFallbacks {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path),
               url.standardizedFileURL != selfAppURL.standardizedFileURL {
                return url
            }
        }
        return nil
    }
}
