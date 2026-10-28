import Foundation
import DotJSONCore

/// UserDefaults-backed app preferences (injectable suite for tests).
struct AppPreferences {
    enum StorageKey {
        static let restoreSession = "dotjson.restoreSession"
        static let defaultIndent = "dotjson.defaultIndent"
        static let formatOnOpen = "dotjson.formatOnOpen"
        static let formatOnPaste = "dotjson.formatOnPaste"
    }

    enum DefaultIndentEncoding: String, Sendable {
        case twoSpaces
        case fourSpaces
        case tab
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var restoreSession: Bool {
        get {
            if defaults.object(forKey: StorageKey.restoreSession) == nil {
                return true
            }
            return defaults.bool(forKey: StorageKey.restoreSession)
        }
        nonmutating set {
            defaults.set(newValue, forKey: StorageKey.restoreSession)
        }
    }

    var formatOnOpen: Bool {
        get {
            if defaults.object(forKey: StorageKey.formatOnOpen) == nil {
                return true
            }
            return defaults.bool(forKey: StorageKey.formatOnOpen)
        }
        nonmutating set {
            defaults.set(newValue, forKey: StorageKey.formatOnOpen)
        }
    }

    var formatOnPaste: Bool {
        get {
            if defaults.object(forKey: StorageKey.formatOnPaste) == nil {
                return true
            }
            return defaults.bool(forKey: StorageKey.formatOnPaste)
        }
        nonmutating set {
            defaults.set(newValue, forKey: StorageKey.formatOnPaste)
        }
    }

    var defaultIndent: JSONFormatter.Indent {
        get {
            guard let raw = defaults.string(forKey: StorageKey.defaultIndent),
                  let encoding = DefaultIndentEncoding(rawValue: raw) else {
                return .fourSpaces
            }
            switch encoding {
            case .twoSpaces: return .twoSpaces
            case .fourSpaces: return .fourSpaces
            case .tab: return .tab
            }
        }
        nonmutating set {
            let encoding: DefaultIndentEncoding
            switch newValue {
            case .twoSpaces: encoding = .twoSpaces
            case .fourSpaces: encoding = .fourSpaces
            case .tab: encoding = .tab
            }
            defaults.set(encoding.rawValue, forKey: StorageKey.defaultIndent)
        }
    }

    /// Removes preference keys written by this type (does not touch workspace snapshot).
    func clearPreferenceKeys() {
        defaults.removeObject(forKey: StorageKey.restoreSession)
        defaults.removeObject(forKey: StorageKey.defaultIndent)
        defaults.removeObject(forKey: StorageKey.formatOnOpen)
        defaults.removeObject(forKey: StorageKey.formatOnPaste)
    }
}
