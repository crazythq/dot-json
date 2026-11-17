import Foundation

enum UpdateURLs {
    static let releasesList = URL(string: "https://github.com/crazythq/dot-json/releases")!
}

struct UpdateChecker: Sendable {
    private let client: UpdateHTTPClient
    private let localVersionProvider: @Sendable () -> String?
    private let repository: String

    init(
        client: UpdateHTTPClient = URLSessionUpdateHTTPClient(),
        localVersionProvider: @escaping @Sendable () -> String? = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        },
        repository: String = "crazythq/dot-json"
    ) {
        self.client = client
        self.localVersionProvider = localVersionProvider
        self.repository = repository
    }

    /// Accepts only https://github.com/<repository>/... release pages.
    static func isTrustedReleaseURL(_ url: URL, repository: String = "crazythq/dot-json") -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return false }
        guard let host = url.host?.lowercased(), host == "github.com" else { return false }
        let path = url.path
        let prefix = "/\(repository)"
        return path == prefix || path.hasPrefix(prefix + "/")
    }

    func check() async -> UpdateCheckResult {
        guard let localRaw = localVersionProvider(),
              let local = SemanticVersion.parse(localRaw) else {
            return .invalidResponse
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return .invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DotJSON-UpdateCheck", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch is CancellationError {
            return .cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            return .cancelled
        } catch {
            return .unreachable
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return .unreachable
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let releaseURL = URL(string: htmlURLString),
              Self.isTrustedReleaseURL(releaseURL, repository: repository),
              let remote = SemanticVersion.parse(tagName) else {
            return .invalidResponse
        }

        let normalized = "\(remote.major).\(remote.minor).\(remote.patch)"
        switch SemanticVersion.compare(remote, local) {
        case .orderedDescending:
            return .available(version: normalized, releaseURL: releaseURL)
        case .orderedSame, .orderedAscending:
            return .upToDate
        }
    }
}
