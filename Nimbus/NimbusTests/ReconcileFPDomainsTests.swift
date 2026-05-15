import Testing
@testable import Nimbus

@Suite("reconcileFPDomains")
@MainActor
struct ReconcileFPDomainsTests {
    @Test func domainMatchingConfigPopulatesMountedIDs() {
        let configs = [
            MountConfig(remote: "gdrive:", mountPoint: "", vfsMode: .readWrite,
                        autoMount: false, backend: .fileProvider)
        ]
        let domains = [FPDomainInfo(identifier: configs[0].id, displayName: "gdrive")]
        var mountedIDs: Set<String> = []
        var logMessages: [String] = []

        reconcileFPDomains(domains, configs: configs, mountedIDs: &mountedIDs) {
            logMessages.append($0)
        }

        #expect(mountedIDs == [configs[0].id])
        #expect(logMessages.isEmpty)
    }

    @Test func orphanDomainIsIgnored() {
        let domains = [FPDomainInfo(identifier: "stale-id", displayName: "old")]
        let configs: [MountConfig] = []
        var mountedIDs: Set<String> = []

        reconcileFPDomains(domains, configs: configs, mountedIDs: &mountedIDs) { _ in }

        #expect(mountedIDs.isEmpty)
    }

    @Test func configWithoutDomainIsLogged() {
        let configs = [
            MountConfig(remote: "gdrive:", mountPoint: "", vfsMode: .readWrite,
                        autoMount: false, backend: .fileProvider)
        ]
        let domains: [FPDomainInfo] = []
        var mountedIDs: Set<String> = []
        var logMessages: [String] = []

        reconcileFPDomains(domains, configs: configs, mountedIDs: &mountedIDs) {
            logMessages.append($0)
        }

        #expect(mountedIDs.isEmpty)
        #expect(logMessages.count == 1)
        #expect(logMessages[0].contains(configs[0].id))
    }

    @Test func emptyInputsAreNoOp() {
        var mountedIDs: Set<String> = ["preexisting"]
        var logMessages: [String] = []

        reconcileFPDomains([], configs: [], mountedIDs: &mountedIDs) {
            logMessages.append($0)
        }

        #expect(mountedIDs == ["preexisting"])  // not cleared
        #expect(logMessages.isEmpty)
    }
}
