import Foundation
import Testing
@testable import DotJSON

@MainActor
struct UpdatePromptCoordinatorTests {
    private static let apiURL = URL(
        string: "https://api.github.com/repos/crazythq/dot-json/releases/latest"
    )!
    private static let releaseURL = URL(
        string: "https://github.com/crazythq/dot-json/releases/tag/v1.2.0"
    )!

    private func isolatedDefaults() -> UserDefaults {
        let suite = "UpdatePromptCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func okPayload(
        tag: String = "v1.2.0",
        htmlURL: String = "https://github.com/crazythq/dot-json/releases/tag/v1.2.0"
    ) throws -> (Data, URLResponse) {
        let data = try JSONSerialization.data(withJSONObject: [
            "tag_name": tag,
            "html_url": htmlURL,
        ] as [String: Any])
        let response = HTTPURLResponse(
            url: Self.apiURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        _ condition: @MainActor () async -> Bool
    ) async {
        let step: UInt64 = 20_000_000
        var waited: UInt64 = 0
        while waited < timeoutNanoseconds {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: step)
            waited += step
        }
    }

    // MARK: - Stubs

    private actor CountingClient: UpdateHTTPClient {
        private(set) var callCount = 0
        private let result: Result<(Data, URLResponse), Error>

        init(result: Result<(Data, URLResponse), Error>) {
            self.result = result
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            callCount += 1
            return try result.get()
        }
    }

    private actor HangClient: UpdateHTTPClient {
        private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
        private(set) var callCount = 0

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            callCount += 1
            return try await withCheckedThrowingContinuation { cont in
                continuation = cont
            }
        }

        func resume(with result: Result<(Data, URLResponse), Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    /// First request waits until cancelled or `finishFirstRequest()`; later requests return `success`.
    private actor CancelAwareClient: UpdateHTTPClient {
        private let success: (Data, URLResponse)
        private var firstContinuation: CheckedContinuation<(Data, URLResponse), Error>?
        private(set) var callCount = 0

        init(success: (Data, URLResponse)) {
            self.success = success
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            callCount += 1
            if callCount == 1 {
                return try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { cont in
                        firstContinuation = cont
                    }
                } onCancel: {
                    Task { await self.resumeFirst(with: .failure(CancellationError())) }
                }
            }
            return success
        }

        func finishFirstRequest() {
            resumeFirst(with: .success(success))
        }

        private func resumeFirst(with result: Result<(Data, URLResponse), Error>) {
            guard let cont = firstContinuation else { return }
            firstContinuation = nil
            cont.resume(with: result)
        }
    }

    @MainActor
    private final class StubAlerter: UpdateAlerter {
        private(set) var availableVersions: [String] = []
        private(set) var upToDateCount = 0
        private(set) var failedCount = 0
        private(set) var lastOnDownload: (() -> Void)?
        private(set) var lastOnSkip: (() -> Void)?
        private(set) var lastOnRemindLater: (() -> Void)?
        private(set) var lastOnOpenReleases: (() -> Void)?

        func presentAvailable(
            version: String,
            onDownload: @escaping () -> Void,
            onSkip: @escaping () -> Void,
            onRemindLater: @escaping () -> Void
        ) {
            availableVersions.append(version)
            lastOnDownload = onDownload
            lastOnSkip = onSkip
            lastOnRemindLater = onRemindLater
        }

        func presentUpToDate() {
            upToDateCount += 1
        }

        func presentCheckFailed(onOpenReleases: @escaping () -> Void) {
            failedCount += 1
            lastOnOpenReleases = onOpenReleases
        }
    }

    // MARK: - Cases

    @Test func automaticDoesNotCallClientWhenAutoCheckDisabled() async throws {
        let client = CountingClient(result: .success(try okPayload()))
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.autoCheckUpdates = false
        let alerter = StubAlerter()

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter
        )

        coordinator.runAutomaticCheckIfNeeded()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(await client.callCount == 0)
        #expect(alerter.availableVersions.isEmpty)
    }

    @Test func automaticSkipsPresentWhenVersionAlreadySkipped() async throws {
        let client = CountingClient(result: .success(try okPayload()))
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.skippedUpdateVersion = "1.2.0"
        let alerter = StubAlerter()

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter
        )

        coordinator.runAutomaticCheckIfNeeded()
        await waitUntil {
            let count = await client.callCount
            return count >= 1
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(alerter.availableVersions.isEmpty)
    }

    @Test func automaticPresentsWhenAvailableAndNotSkipped() async throws {
        let client = CountingClient(result: .success(try okPayload()))
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let alerter = StubAlerter()

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter
        )

        coordinator.runAutomaticCheckIfNeeded()
        await waitUntil { !alerter.availableVersions.isEmpty }

        #expect(alerter.availableVersions == ["1.2.0"])
    }

    @Test func manualPresentsEvenWhenVersionSkipped() async throws {
        let client = CountingClient(result: .success(try okPayload()))
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.skippedUpdateVersion = "1.2.0"
        let alerter = StubAlerter()

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter
        )

        coordinator.runManualCheck()
        await waitUntil { !alerter.availableVersions.isEmpty }

        #expect(alerter.availableVersions == ["1.2.0"])
    }

    @Test func manualUnreachablePresentsFailureAndOpensReleasesList() async throws {
        let client = CountingClient(result: .failure(URLError(.timedOut)))
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let alerter = StubAlerter()
        var openedURLs: [URL] = []

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter,
            urlOpener: { openedURLs.append($0) }
        )

        coordinator.runManualCheck()
        await waitUntil { alerter.failedCount >= 1 }

        #expect(alerter.failedCount == 1)
        alerter.lastOnOpenReleases?()
        #expect(openedURLs == [UpdateURLs.releasesList])
    }

    @Test func skipCallbackWritesSkippedUpdateVersion() async throws {
        let client = CountingClient(result: .success(try okPayload()))
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let alerter = StubAlerter()

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter
        )

        coordinator.runAutomaticCheckIfNeeded()
        await waitUntil { !alerter.availableVersions.isEmpty }

        alerter.lastOnSkip?()
        #expect(prefs.skippedUpdateVersion == "1.2.0")
    }

    @Test func secondAutomaticAfterCompletionDoesNotCallClientAgain() async throws {
        let client = CountingClient(result: .success(try okPayload()))
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let alerter = StubAlerter()

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter
        )

        coordinator.runAutomaticCheckIfNeeded()
        await waitUntil { !alerter.availableVersions.isEmpty }
        #expect(await client.callCount == 1)

        coordinator.runAutomaticCheckIfNeeded()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(await client.callCount == 1)
        #expect(alerter.availableVersions.count == 1)
    }

    @Test func secondAutomaticIgnoredWhileFirstInFlight() async throws {
        let hang = HangClient()
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let alerter = StubAlerter()

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: hang, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter
        )

        coordinator.runAutomaticCheckIfNeeded()
        await waitUntil {
            let count = await hang.callCount
            return count >= 1
        }

        coordinator.runAutomaticCheckIfNeeded()
        try? await Task.sleep(nanoseconds: 100_000_000)

        let callCountAfterSecond = await hang.callCount
        #expect(callCountAfterSecond == 1)

        let payload = try okPayload()
        await hang.resume(with: .success(payload))
        await waitUntil { !alerter.availableVersions.isEmpty }

        #expect(alerter.availableVersions.count == 1)
        #expect(alerter.availableVersions == ["1.2.0"])
    }

    @Test func shouldPresentAvailableRespectsModeAndSkip() {
        #expect(
            UpdatePromptCoordinator.shouldPresentAvailable(
                version: "1.2.0",
                mode: .automatic,
                skipped: "1.2.0"
            ) == false
        )
        #expect(
            UpdatePromptCoordinator.shouldPresentAvailable(
                version: "1.2.0",
                mode: .automatic,
                skipped: nil
            ) == true
        )
        #expect(
            UpdatePromptCoordinator.shouldPresentAvailable(
                version: "1.2.0",
                mode: .manual,
                skipped: "1.2.0"
            ) == true
        )
    }

    @Test func downloadCallbackOpensReleaseURL() async throws {
        let client = CountingClient(result: .success(try okPayload()))
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let alerter = StubAlerter()
        var openedURLs: [URL] = []

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter,
            urlOpener: { openedURLs.append($0) }
        )

        coordinator.runManualCheck()
        await waitUntil { !alerter.availableVersions.isEmpty }

        alerter.lastOnDownload?()
        #expect(openedURLs == [Self.releaseURL])
    }

    @Test func automaticUnreachableDoesNotPresentFailure() async throws {
        let client = CountingClient(result: .failure(URLError(.timedOut)))
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let alerter = StubAlerter()

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter
        )

        coordinator.runAutomaticCheckIfNeeded()
        await waitUntil {
            let count = await client.callCount
            return count >= 1
        }
        try? await Task.sleep(nanoseconds: 80_000_000)

        #expect(alerter.failedCount == 0)
        #expect(alerter.upToDateCount == 0)
        #expect(alerter.availableVersions.isEmpty)
    }

    @Test func manualCancelsInFlightAutomaticAndPresentsOwnResult() async throws {
        let client = CancelAwareClient(success: try okPayload())
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let alerter = StubAlerter()

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter
        )

        coordinator.runAutomaticCheckIfNeeded()
        await waitUntil {
            let count = await client.callCount
            return count >= 1
        }

        coordinator.runManualCheck()
        await waitUntil { !alerter.availableVersions.isEmpty }

        #expect(await client.callCount == 2)
        #expect(alerter.availableVersions == ["1.2.0"])
        #expect(alerter.failedCount == 0)
    }

    @Test func automaticDoesNotConsumeSessionSlotWhileManualInFlight() async throws {
        let client = CancelAwareClient(success: try okPayload())
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let alerter = StubAlerter()

        let coordinator = UpdatePromptCoordinator(
            checkerFactory: {
                UpdateChecker(client: client, localVersionProvider: { "1.1.5" })
            },
            preferences: prefs,
            alerter: alerter
        )

        coordinator.runManualCheck()
        await waitUntil {
            let count = await client.callCount
            return count >= 1
        }

        coordinator.runAutomaticCheckIfNeeded()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await client.callCount == 1)

        await client.finishFirstRequest()
        await waitUntil { !alerter.availableVersions.isEmpty }
        #expect(alerter.availableVersions.count == 1)

        coordinator.runAutomaticCheckIfNeeded()
        await waitUntil {
            let count = await client.callCount
            return count >= 2
        }
        #expect(await client.callCount == 2)
    }
}
