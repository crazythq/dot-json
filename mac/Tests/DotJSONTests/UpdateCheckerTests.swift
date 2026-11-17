import Foundation
import Testing
@testable import DotJSON

struct UpdateCheckerTests {
    private struct StubClient: UpdateHTTPClient {
        let result: Result<(Data, URLResponse), Error>

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            try result.get()
        }
    }

    private static let apiURL = URL(
        string: "https://api.github.com/repos/crazythq/dot-json/releases/latest"
    )!

    private func jsonResponse(_ object: [String: Any], status: Int = 200) throws -> (Data, URLResponse) {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(
            url: Self.apiURL,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    private func okPayload(
        tag: String = "v1.2.0",
        htmlURL: String = "https://github.com/crazythq/dot-json/releases/tag/v1.2.0"
    ) throws -> (Data, URLResponse) {
        try jsonResponse([
            "tag_name": tag,
            "html_url": htmlURL,
        ])
    }

    @Test func availableWhenRemoteNewer() async throws {
        let client = StubClient(result: .success(try okPayload()))
        let checker = UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
        let result = await checker.check()
        #expect(result == .available(
            version: "1.2.0",
            releaseURL: URL(string: "https://github.com/crazythq/dot-json/releases/tag/v1.2.0")!
        ))
    }

    @Test func upToDateWhenEqual() async throws {
        let client = StubClient(result: .success(try okPayload(
            tag: "v1.1.5",
            htmlURL: "https://github.com/crazythq/dot-json/releases/tag/v1.1.5"
        )))
        let checker = UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
        #expect(await checker.check() == .upToDate)
    }

    @Test func upToDateWhenRemoteOlder() async throws {
        let client = StubClient(result: .success(try okPayload(
            tag: "1.0.0",
            htmlURL: "https://github.com/crazythq/dot-json/releases/tag/1.0.0"
        )))
        let checker = UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
        #expect(await checker.check() == .upToDate)
    }

    @Test func unreachableOnHTTPError() async throws {
        let response = HTTPURLResponse(
            url: Self.apiURL,
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        )!
        let client = StubClient(result: .success((Data(), response)))
        let checker = UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
        #expect(await checker.check() == .unreachable)
    }

    @Test func unreachableOnThrownError() async throws {
        let client = StubClient(result: .failure(URLError(.timedOut)))
        let checker = UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
        #expect(await checker.check() == .unreachable)
    }

    @Test func invalidResponseOnBadJSON() async throws {
        let response = HTTPURLResponse(
            url: Self.apiURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let client = StubClient(result: .success((Data("not-json".utf8), response)))
        let checker = UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
        #expect(await checker.check() == .invalidResponse)
    }

    @Test func invalidResponseOnBadTag() async throws {
        let client = StubClient(result: .success(try okPayload(tag: "nope")))
        let checker = UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
        #expect(await checker.check() == .invalidResponse)
    }

    @Test func invalidResponseWhenLocalVersionMissing() async throws {
        let client = StubClient(result: .success(try okPayload()))
        let checker = UpdateChecker(client: client, localVersionProvider: { nil })
        #expect(await checker.check() == .invalidResponse)
    }

    @Test(arguments: [
        "http://github.com/crazythq/dot-json/releases/tag/v1.2.0",
        "https://evil.example/crazythq/dot-json/releases/tag/v1.2.0",
        "https://github.com.evil.example/crazythq/dot-json/releases/tag/v1.2.0",
        "https://github.com/other/repo/releases/tag/v1.2.0",
        "file:///tmp/evil",
        "javascript:alert(1)",
    ])
    func invalidResponseOnUntrustedReleaseURL(htmlURL: String) async throws {
        let client = StubClient(result: .success(try okPayload(htmlURL: htmlURL)))
        let checker = UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
        #expect(await checker.check() == .invalidResponse)
    }

    @Test func cancelledWhenClientThrowsCancellationError() async throws {
        let client = StubClient(result: .failure(CancellationError()))
        let checker = UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
        #expect(await checker.check() == UpdateCheckResult.cancelled)
    }

    @Test func cancelledWhenClientThrowsURLErrorCancelled() async throws {
        let client = StubClient(result: .failure(URLError(.cancelled)))
        let checker = UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
        #expect(await checker.check() == UpdateCheckResult.cancelled)
    }
}
