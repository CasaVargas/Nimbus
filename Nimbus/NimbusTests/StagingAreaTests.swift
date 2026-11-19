import Foundation
import Testing

@testable import Nimbus

@Suite("StagingArea")
struct StagingAreaTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-staging-area-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func instanceFoldersNestByPIDInContainerTemp() throws {
        let containerTemp = try scratch()
        defer { try? FileManager.default.removeItem(at: containerTemp) }
        let staging = StagingArea(containerTemp: containerTemp)
        let id = UUID()

        let expected = containerTemp
            .appendingPathComponent("app.casavargas.nimbus.FileProvider", isDirectory: true)
            .appendingPathComponent("100", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        #expect(staging.makeInstanceFolder(pid: 100, id: id) == expected)
        // Sibling instances in one process get their own folders.
        #expect(staging.makeInstanceFolder() != staging.makeInstanceFolder())
        // Callers create the folder when they first write.
        #expect(!FileManager.default.fileExists(atPath: expected.path))
    }

    @Test func currentProcessCountsAsAlive() {
        #expect(StagingArea.processIsAlive(getpid()))
    }

    @Test func removeOrphansRemovesLegacyAndDeadProcessFolders() throws {
        let containerTemp = try scratch()
        defer { try? FileManager.default.removeItem(at: containerTemp) }
        let fm = FileManager.default
        let staging = StagingArea(containerTemp: containerTemp)
        let root = staging.folder

        let legacyDownloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let legacyThumbnails = root.appendingPathComponent("Thumbnails", isDirectory: true)
        let dead = staging.makeInstanceFolder(pid: 222)
        let live = staging.makeInstanceFolder(pid: 111)
        let current = staging.makeInstanceFolder(pid: 333)
        let notAPID = root.appendingPathComponent("not-a-pid", isDirectory: true)
        for dir in [legacyDownloads, legacyThumbnails, dead, live, current, notAPID] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Named like a dead process's folder, but not real folders.
        let file = root.appendingPathComponent("444")
        try Data("x".utf8).write(to: file)
        let target = containerTemp.appendingPathComponent("target", isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("555")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)

        staging.removeOrphans(currentPID: 333, isAlive: { $0 == 111 })

        #expect(!fm.fileExists(atPath: legacyDownloads.path))
        #expect(!fm.fileExists(atPath: legacyThumbnails.path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("222").path))

        #expect(fm.fileExists(atPath: live.path))
        #expect(fm.fileExists(atPath: current.path))
        #expect(fm.fileExists(atPath: notAPID.path))
        #expect(fm.fileExists(atPath: file.path))
        #expect((try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil)
        #expect(fm.fileExists(atPath: target.path))
    }
}
