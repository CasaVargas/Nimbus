import Testing
import Foundation
@testable import Nimbus
@testable import RcloneKit

@Suite("RemoteStatusService")
@MainActor
struct RemoteStatusServiceTests {
    /// Every service gets throwaway defaults. The test host runs as
    /// app.casavargas.nimbus, so `.standard` here is the real app's settings
    /// file: probes used to leave `remoteLastConnected` entries for test
    /// remotes ("gdrive", "s3") in the user's Nimbus preferences.
    static func isolatedDefaults() -> UserDefaults {
        let defaults = ScratchDefaults.make("RemoteStatus")
        return defaults
    }

    @Test func probeSetsConnectedOnSuccess() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .success(MockRcloneClient.emptyAbout())
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        await service.probe("gdrive")
        #expect(service.statuses["gdrive"] == .connected)
        #expect(client.calls == ["gdrive:"])
    }

    @Test func probeSetsUnknownBeforeCompletion() async {
        let client = MockRcloneClient()
        client.aboutResults["slow:"] = .success(MockRcloneClient.emptyAbout())
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        service.markUnknown("slow")  // simulates the initial set before probeAll launches
        #expect(service.statuses["slow"] == .unknown)
    }

    @Test func probeSetsAuthNeededOn401() async {
        let client = MockRcloneClient()
        client.aboutResults["s3:"] = .failure(
            RcloneError.requestFailed(status: 401, message: "Unauthorized")
        )
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        await service.probe("s3")
        #expect(service.statuses["s3"] == .authNeeded)
    }

    @Test func probeSetsAuthNeededOn403() async {
        let client = MockRcloneClient()
        client.aboutResults["s3:"] = .failure(
            RcloneError.requestFailed(status: 403, message: "Forbidden")
        )
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        await service.probe("s3")
        #expect(service.statuses["s3"] == .authNeeded)
    }

    @Test func probeSetsAuthNeededOnTokenMessage() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .failure(
            RcloneError.requestFailed(status: 500, message: "couldn't fetch info: oauth token expired")
        )
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        await service.probe("gdrive")
        #expect(service.statuses["gdrive"] == .authNeeded)
    }

    @Test func probeSetsUnreachableOnConnectionRefused() async {
        let client = MockRcloneClient()
        client.aboutResults["s3:"] = .failure(
            RcloneError.requestFailed(status: 500, message: "couldn't fetch info: connection refused")
        )
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        await service.probe("s3")
        if case .unreachable(let reason) = service.statuses["s3"] {
            #expect(reason.contains("connection refused"))
        } else {
            Issue.record("Expected .unreachable, got \(String(describing: service.statuses["s3"]))")
        }
    }

    @Test func probeAllRunsInParallel() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .success(MockRcloneClient.emptyAbout())
        client.aboutResults["s3:"] = .success(MockRcloneClient.emptyAbout())
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        await service.probeAll(["gdrive", "s3"])
        #expect(service.statuses["gdrive"] == .connected)
        #expect(service.statuses["s3"] == .connected)
        #expect(Set(client.calls) == ["gdrive:", "s3:"])
    }

    @Test func clearRemovesStatus() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .success(MockRcloneClient.emptyAbout())
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        await service.probe("gdrive")
        #expect(service.statuses["gdrive"] == .connected)
        service.clear("gdrive")
        #expect(service.statuses["gdrive"] == nil)
    }

    @Test func probeIgnoresEmptyName() async {
        let client = MockRcloneClient()
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        await service.probe("")
        #expect(client.calls.isEmpty)
        #expect(service.statuses[""] == nil)
    }

    @Test func classifyDetectsAuthOnUnauthorizedSubstring() {
        let err = RcloneError.requestFailed(status: 500, message: "request: unauthorized client")
        #expect(RemoteStatusService.classify(err) == .authNeeded)
    }

    @Test func classifyDetectsAuthOnForbiddenSubstring() {
        let err = RcloneError.requestFailed(status: 500, message: "got 'forbidden' from backend")
        #expect(RemoteStatusService.classify(err) == .authNeeded)
    }
    @Test func classifyKeepsConfigFailuresAsError() {
        let err = RcloneError.requestFailed(status: 500, message: "didn't find section in config file")
        if case .error = RemoteStatusService.classify(err) {} else {
            Issue.record("expected .error, got \(RemoteStatusService.classify(err))")
        }
    }

    @Test func classifyMapsCannotConnectToUnreachable() {
        let err = URLError(.cannotConnectToHost)
        if case .unreachable = RemoteStatusService.classify(err) {} else {
            Issue.record("expected .unreachable, got \(RemoteStatusService.classify(err))")
        }
    }

    @Test func successfulProbeRecordsAndPersistsLastConnected() async throws {
        let defaults = ScratchDefaults.make("RemoteStatus")
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let client = MockRcloneClient()
        client.aboutResults["nas:"] = .success(MockRcloneClient.emptyAbout())
        let service = RemoteStatusService(client: client, defaults: defaults, now: { stamp })
        await service.probe("nas")
        #expect(service.lastConnected["nas"] == stamp)
        let reloaded = RemoteStatusService(client: client, defaults: defaults)
        #expect(reloaded.lastConnected["nas"] == stamp)
        reloaded.clear("nas")
        #expect(RemoteStatusService(client: client, defaults: defaults).lastConnected["nas"] == nil)
    }

    @Test func failedProbeKeepsPreviousLastConnected() async throws {
        let defaults = ScratchDefaults.make("RemoteStatus")
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let client = MockRcloneClient()
        client.aboutResults["nas:"] = .success(MockRcloneClient.emptyAbout())
        let service = RemoteStatusService(client: client, defaults: defaults, now: { stamp })
        await service.probe("nas")
        client.aboutResults["nas:"] = .failure(RcloneError.requestFailed(status: 500, message: "dial tcp: no route to host"))
        await service.probe("nas")
        #expect(service.lastConnected["nas"] == stamp)
    }

    // MARK: - Services without `about` (issue #139: Backblaze B2)

    static let unsupportedAbout = RcloneError.requestFailed(
        status: 500, message: "B2 root doesn't support about")

    @Test func probeFallsBackToListingWhenAboutIsUnsupported() async {
        let defaults = Self.isolatedDefaults()
        let client = MockRcloneClient()
        client.aboutResults["b2:"] = .failure(Self.unsupportedAbout)
        let service = RemoteStatusService(client: client, defaults: defaults)
        await service.probe("b2")
        #expect(service.statuses["b2"] == .connected)
        #expect(service.quotas["b2"] == nil)
        #expect(service.lastConnected["b2"] != nil)
        #expect(client.listCalls == ["b2:"])
    }

    @Test func unsupportedAboutStillReportsBadCredentials() async {
        let client = MockRcloneClient()
        client.aboutResults["b2:"] = .failure(Self.unsupportedAbout)
        client.listResults["b2:"] = .failure(
            RcloneError.requestFailed(status: 500, message: "failed to authorize account: 401 unauthorized"))
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        await service.probe("b2")
        #expect(service.statuses["b2"] == .authNeeded)
    }

    @Test func otherAboutFailuresDoNotFallBackToListing() async {
        let client = MockRcloneClient()
        client.aboutResults["s3:"] = .failure(
            RcloneError.requestFailed(status: 500, message: "didn't find section in config file"))
        let service = RemoteStatusService(client: client, defaults: Self.isolatedDefaults())
        await service.probe("s3")
        if case .error = service.statuses["s3"] {} else {
            Issue.record("expected .error, got \(String(describing: service.statuses["s3"]))")
        }
        #expect(client.listCalls.isEmpty)
    }
}
