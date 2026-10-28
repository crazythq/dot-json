import Foundation

/// UserDefaults-backed storage for pre-DotJSON default handler app URLs.
struct PriorHandlerStore {
    private enum Key {
        static let json = "sh.crazy.dotjson.fileAssociation.prior.json"
        static let jsonl = "sh.crazy.dotjson.fileAssociation.prior.jsonl"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PriorHandlerSnapshot {
        PriorHandlerSnapshot(
            jsonAppURL: url(forKey: Key.json),
            jsonlAppURL: url(forKey: Key.jsonl)
        )
    }

    func save(_ snapshot: PriorHandlerSnapshot) {
        write(snapshot.jsonAppURL, forKey: Key.json)
        write(snapshot.jsonlAppURL, forKey: Key.jsonl)
    }

    /// Merge non-nil entries from `snapshot` without clearing the other extension’s prior.
    func merge(_ snapshot: PriorHandlerSnapshot) {
        var current = load()
        if let json = snapshot.jsonAppURL {
            current.jsonAppURL = json
        }
        if let jsonl = snapshot.jsonlAppURL {
            current.jsonlAppURL = jsonl
        }
        save(current)
    }

    func clear() {
        defaults.removeObject(forKey: Key.json)
        defaults.removeObject(forKey: Key.jsonl)
    }

    func clear(for ext: ManagedJSONExtension) {
        switch ext {
        case .json:
            defaults.removeObject(forKey: Key.json)
        case .jsonl:
            defaults.removeObject(forKey: Key.jsonl)
        }
    }

    private func url(forKey key: String) -> URL? {
        guard let path = defaults.string(forKey: key), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func write(_ url: URL?, forKey key: String) {
        if let url {
            defaults.set(url.path, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
