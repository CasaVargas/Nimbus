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
        // Production contract: domains are registered under the bare remote
        // name (remoteNameOnly), never under config.id.
        let domains = [FPDomainInfo(identifier: "gdrive", displayName: "gdrive")]
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

    @Test func configWithoutDomainIsLoggedAndDropped() {
        let configs = [
            MountConfig(remote: "gdrive:", mountPoint: "", vfsMode: .readWrite,
                        autoMount: false, backend: .fileProvider)
        ]
        let domains: [FPDomainInfo] = []
        var mountedIDs: Set<String> = [configs[0].id]
        var logMessages: [String] = []

        reconcileFPDomains(domains, configs: configs, mountedIDs: &mountedIDs) {
            logMessages.append($0)
        }

        #expect(mountedIDs.isEmpty)  // vanished domain drops the stale id
        #expect(logMessages.count == 1)
        #expect(logMessages[0].contains(configs[0].id))
    }

    @Test func nfsConfigsAreIgnored() {
        let configs = [
            MountConfig(remote: "gdrive:", mountPoint: "/Users/x/GDrive",
                        vfsMode: .readWrite, autoMount: false, backend: .nfs)
        ]
        // Even with a same-named domain live, an NFS config's state must not
        // be driven by File Provider domains.
        let domains = [FPDomainInfo(identifier: "gdrive", displayName: "gdrive")]
        var mountedIDs: Set<String> = []
        var logMessages: [String] = []

        reconcileFPDomains(domains, configs: configs, mountedIDs: &mountedIDs) {
            logMessages.append($0)
        }

        #expect(mountedIDs.isEmpty)
        #expect(logMessages.isEmpty)
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
