import Testing
@testable import Nimbus

// Covers the two pure functions behind automount-on-restart:
// `parseStaleMountPoints` (the stale-sweep targeting that once unmounted
// freshly restored volumes) and `configsToRestore` (which mounts come back
// at launch).

@Suite("parseStaleMountPoints")
struct ParseStaleMountPointsTests {
    private let sample = """
    /dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
    devfs on /dev (devfs, local, nobrowse)
    localhost:/ on /Users/me/GoogleDrive (nfs, nosuid, nodev, soft, nobrowse)
    localhost:/ on /Users/me/S3 (nfs, nosuid, nodev, soft, nobrowse)
    //user@server/share on /Volumes/share (smbfs, nodev, nosuid)
    """

    @Test func findsLocalhostNFSMounts() {
        let stale = parseStaleMountPoints(mountOutput: sample, excluding: [])
        #expect(stale == ["/Users/me/GoogleDrive", "/Users/me/S3"])
    }

    @Test func excludesLiveMountsOwnedByThisSession() {
        let stale = parseStaleMountPoints(
            mountOutput: sample,
            excluding: ["/Users/me/GoogleDrive"]
        )
        #expect(stale == ["/Users/me/S3"])
    }

    @Test func ignoresForeignNFSAndNonNFSLines() {
        let output = """
        /dev/disk3s1s1 on / (apfs, local, journaled)
        server:/export on /Users/me/RemoteNFS (nfs)
        localhost:8080 on /Users/me/NotNFS (smbfs)
        """
        #expect(parseStaleMountPoints(mountOutput: output, excluding: []).isEmpty)
    }

    @Test func emptyOutputYieldsNothing() {
        #expect(parseStaleMountPoints(mountOutput: "", excluding: []).isEmpty)
    }
}

@Suite("configsToRestore")
struct ConfigsToRestoreTests {
    private func config(
        _ remote: String,
        mountPoint: String,
        autoMount: Bool = false,
        backend: MountBackend = .nfs
    ) -> MountConfig {
        MountConfig(
            remote: remote,
            mountPoint: mountPoint,
            vfsMode: .readWrite,
            autoMount: autoMount,
            backend: backend
        )
    }

    @Test func autoMountFlaggedConfigsAlwaysRestore() {
        let flagged = config("gdrive:", mountPoint: "/Users/x/GDrive", autoMount: true)
        let restored = configsToRestore(configs: [flagged], lastActiveIDs: [])
        #expect(restored.map(\.id) == [flagged.id])
    }

    @Test func lastActiveConfigsRestoreWithoutTheFlag() {
        let wasUp = config("s3:", mountPoint: "/Users/x/S3")
        let restored = configsToRestore(configs: [wasUp], lastActiveIDs: [wasUp.id])
        #expect(restored.map(\.id) == [wasUp.id])
    }

    @Test func inactiveUnflaggedConfigsStayDown() {
        let dormant = config("dropbox:", mountPoint: "/Users/x/Dropbox")
        #expect(configsToRestore(configs: [dormant], lastActiveIDs: []).isEmpty)
    }

    @Test func fileProviderConfigsNeverRestore() {
        let fp = config(
            "gdrive:",
            mountPoint: "/Users/x/GDriveFP",
            autoMount: true,
            backend: .fileProvider
        )
        #expect(configsToRestore(configs: [fp], lastActiveIDs: [fp.id]).isEmpty)
    }

    @Test func mixedConfigsPreserveOrderAndUnionSemantics() {
        let flagged = config("a:", mountPoint: "/Users/x/A", autoMount: true)
        let wasUp = config("b:", mountPoint: "/Users/x/B")
        let dormant = config("c:", mountPoint: "/Users/x/C")
        let restored = configsToRestore(
            configs: [flagged, wasUp, dormant],
            lastActiveIDs: [wasUp.id]
        )
        #expect(restored.map(\.id) == [flagged.id, wasUp.id])
    }
}
