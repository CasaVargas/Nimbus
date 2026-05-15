import Testing
import Foundation
@testable import Nimbus
@testable import RcloneKit

@Suite("RemoteStatusService")
@MainActor
struct RemoteStatusServiceTests {
    @Test func probeSetsConnectedOnSuccess() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .success(MockRcloneClient.emptyAbout())
        let service = RemoteStatusService(client: client)
        await service.probe("gdrive")
        #expect(service.statuses["gdrive"] == .connected)
        #expect(client.calls == ["gdrive:"])
    }

    @Test func probeSetsUnknownBeforeCompletion() async {
        let client = MockRcloneClient()
        client.aboutResults["slow:"] = .success(MockRcloneClient.emptyAbout())
        let service = RemoteStatusService(client: client)
        service.markUnknown("slow")  // simulates the initial set before probeAll launches
        #expect(service.statuses["slow"] == .unknown)
    }

    @Test func probeSetsAuthNeededOn401() async {
        let client = MockRcloneClient()
        client.aboutResults["s3:"] = .failure(
            RcloneError.requestFailed(status: 401, message: "Unauthorized")
        )
        let service = RemoteStatusService(client: client)
        await service.probe("s3")
        #expect(service.statuses["s3"] == .authNeeded)
    }

    @Test func probeSetsAuthNeededOn403() async {
        let client = MockRcloneClient()
        client.aboutResults["s3:"] = .failure(
            RcloneError.requestFailed(status: 403, message: "Forbidden")
        )
        let service = RemoteStatusService(client: client)
        await service.probe("s3")
        #expect(service.statuses["s3"] == .authNeeded)
    }

    @Test func probeSetsAuthNeededOnTokenMessage() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .failure(
            RcloneError.requestFailed(status: 500, message: "couldn't fetch info: oauth token expired")
        )
        let service = RemoteStatusService(client: client)
        await service.probe("gdrive")
        #expect(service.statuses["gdrive"] == .authNeeded)
    }

    @Test func probeSetsErrorOnGenericFailure() async {
        let client = MockRcloneClient()
        client.aboutResults["s3:"] = .failure(
            RcloneError.requestFailed(status: 500, message: "couldn't fetch info: connection refused")
        )
        let service = RemoteStatusService(client: client)
        await service.probe("s3")
        if case .error(let reason) = service.statuses["s3"] {
            #expect(reason.contains("connection refused"))
        } else {
            Issue.record("Expected .error, got \(String(describing: service.statuses["s3"]))")
        }
    }

    @Test func probeAllRunsInParallel() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .success(MockRcloneClient.emptyAbout())
        client.aboutResults["s3:"] = .success(MockRcloneClient.emptyAbout())
        let service = RemoteStatusService(client: client)
        await service.probeAll(["gdrive", "s3"])
        #expect(service.statuses["gdrive"] == .connected)
        #expect(service.statuses["s3"] == .connected)
        #expect(Set(client.calls) == ["gdrive:", "s3:"])
    }

    @Test func clearRemovesStatus() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .success(MockRcloneClient.emptyAbout())
        let service = RemoteStatusService(client: client)
        await service.probe("gdrive")
        #expect(service.statuses["gdrive"] == .connected)
        service.clear("gdrive")
        #expect(service.statuses["gdrive"] == nil)
    }

    @Test func probeIgnoresEmptyName() async {
        let client = MockRcloneClient()
        let service = RemoteStatusService(client: client)
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
}
