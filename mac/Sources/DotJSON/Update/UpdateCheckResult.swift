import Foundation

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case available(version: String, releaseURL: URL)
    case unreachable
    case invalidResponse
    case cancelled
}
