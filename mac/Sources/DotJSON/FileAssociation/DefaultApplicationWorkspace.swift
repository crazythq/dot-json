import AppKit
import Foundation
import UniformTypeIdentifiers

/// Test seam over `NSWorkspace` default-application APIs.
protocol DefaultApplicationWorkspace {
    func defaultApplicationURL(for ext: ManagedJSONExtension) -> URL?
    func setDefaultApplication(at appURL: URL, for ext: ManagedJSONExtension) async throws
    func workspaceCandidate(for ext: ManagedJSONExtension) -> URL?
}

enum DefaultApplicationWorkspaceError: Error, Equatable {
    case setFailed(underlyingDescription: String)
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
                    continuation.resume(
                        throwing: DefaultApplicationWorkspaceError.setFailed(
                            underlyingDescription: error.localizedDescription
                        )
                    )
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
