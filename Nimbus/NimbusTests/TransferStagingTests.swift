import Foundation
import Testing

@testable import Nimbus

@Suite("TransferStaging")
struct TransferStagingTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-transfer-staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func age(_ url: URL, days: Double) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-days * 24 * 60 * 60)], ofItemAtPath: url.path
        )
    }

    @Test func stagedNameKeepsOnlyAPlainExtension() {
        #expect(TransferStaging.stagedName(for: "Q3 Report.pdf") == "content.pdf")
        #expect(TransferStaging.stagedName(for: "archive.tar.GZ") == "content.GZ")
        #expect(TransferStaging.stagedName(for: "README") == "content")
        #expect(TransferStaging.stagedName(for: ".gitignore") == "content")
        #expect(TransferStaging.stagedName(for: "notes.my file") == "content")
        #expect(TransferStaging.stagedName(for: "photo.jpég") == "content")
        #expect(TransferStaging.stagedName(for: "x." + String(repeating: "a", count: 40)) == "content")
        #expect(TransferStaging.stagedName(for: "") == "content")
    }

    @Test func everyTransferGetsItsOwnEmptyFolder() throws {
        let container = try scratch()
        defer { try? FileManager.default.removeItem(at: container) }
        let first = try TransferStaging.makeFolder(in: container)
        let second = try TransferStaging.makeFolder(in: container)

        #expect(first != second)
        for folder in [first, second] {
            #expect(folder.deletingLastPathComponent().lastPathComponent == TransferStaging.folderName)
            let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(contents.isEmpty)
        }
    }

    @Test func sweepRemovesOnlyFoldersNothingChangedIn() throws {
        let container = try scratch()
        defer { try? FileManager.default.removeItem(at: container) }
        let manager = FileManager.default

        let abandoned = try TransferStaging.makeFolder(in: container)
        let abandonedFile = abandoned.appendingPathComponent("content.bin")
        try Data("x".utf8).write(to: abandonedFile)
        try age(abandonedFile, days: 2)
        try age(abandoned, days: 2)

        // An old folder whose file rclone is still writing.
        let running = try TransferStaging.makeFolder(in: container)
        try Data("x".utf8).write(to: running.appendingPathComponent("content.bin.partial"))
        try age(running, days: 2)

        let fresh = try TransferStaging.makeFolder(in: container)

        TransferStaging.sweep(in: container)
        #expect(!manager.fileExists(atPath: abandoned.path))
        #expect(manager.fileExists(atPath: running.path))
        #expect(manager.fileExists(atPath: fresh.path))
    }

    @Test func sweepingAContainerWithNoTransfersDoesNothing() throws {
        let container = try scratch()
        defer { try? FileManager.default.removeItem(at: container) }
        TransferStaging.sweep(in: container)
        #expect(!FileManager.default.fileExists(atPath: TransferStaging.root(in: container).path))
    }
}
