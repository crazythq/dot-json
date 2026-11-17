import Foundation

struct SemanticVersion: Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    static func parse(_ raw: String) -> SemanticVersion? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.first == "v" || s.first == "V" {
            s = String(s.dropFirst())
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), major >= 0,
              let minor = Int(parts[1]), minor >= 0,
              let patch = Int(parts[2]), patch >= 0,
              String(parts[0]) == String(major),
              String(parts[1]) == String(minor),
              String(parts[2]) == String(patch)
        else {
            return nil
        }
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }

    static func compare(_ a: SemanticVersion, _ b: SemanticVersion) -> ComparisonResult {
        if a.major != b.major { return a.major < b.major ? .orderedAscending : .orderedDescending }
        if a.minor != b.minor { return a.minor < b.minor ? .orderedAscending : .orderedDescending }
        if a.patch != b.patch { return a.patch < b.patch ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }
}