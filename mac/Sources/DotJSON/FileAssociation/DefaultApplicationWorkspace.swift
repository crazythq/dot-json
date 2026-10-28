import AppKit
import Foundation
import UniformTypeIdentifiers

/// Test seam over `NSWorkspace` default-application APIs (MainActor; matches coordinator + AppKit).
@MainActor
protocol DefaultApplicationWorkspace {
    func defaultApplicationURL(for ext: ManagedJSONExtension) -> URL?
    func setDefaultApplication(at appURL: URL, for ext: ManagedJSONExtension) async throws
    func workspaceCandidate(for ext: ManagedJSONExtension) -> URL?
}

enum DefaultApplicationWorkspaceError: Error, Equatable {
    case userCancelled
    case setFailed(underlyingDescription: String)

    /// Maps Launch Services / Cocoa errors when the user declines the Finder confirmation sheet.
    static func isUserCancellation(_ error: Error) -> Bool {
        if case DefaultApplicationWorkspaceError.userCancelled = error {
            return true
        }
        return matchesCancellationNSError(error as NSError, visited: [])
    }

    private static func matchesCancellationNSError(_ ns: NSError, visited: Set<ObjectIdentifier>) -> Bool {
        let token = ObjectIdentifier(ns)
        guard !visited.contains(token) else { return false }
        var nextVisited = visited
        nextVisited.insert(token)

        if ns.domain == NSCocoaErrorDomain, ns.code == NSUserCancelledError {
            return true
        }
        if ns.domain == NSCocoaErrorDomain, ns.code == CocoaError.userCancelled.rawValue {
            return true
        }
        if ns.domain == NSOSStatusErrorDomain, ns.code == -128 || ns.code == -60006 {
            return true
        }

        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           matchesCancellationNSError(underlying, visited: nextVisited) {
            return true
        }
        return false
    }

    static func from(_ error: Error) -> DefaultApplicationWorkspaceError {
        if isUserCancellation(error) {
            return .userCancelled
        }
        return .setFailed(underlyingDescription: error.localizedDescription)
    }
}

struct LiveDefaultApplicationWorkspace: DefaultApplicationWorkspace {
    func defaultApplicationURL(for ext: ManagedJSONExtension) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: ext.preferredContentType)
    }

    func workspaceCandidate(for ext: ManagedJSONExtension) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: ext.preferredContentType)
    }

    func setDefaultApplication(at appURL: URL, for ext: ManagedJSONExtension) async throws {
        let type = ext.preferredContentType
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
                if let error {
                    continuation.resume(throwing: DefaultApplicationWorkspaceError.from(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
