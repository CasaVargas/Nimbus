import Foundation
import Testing

@testable import Nimbus

@Suite("ShareInbox")
@MainActor
struct ShareInboxTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-share-inbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Hand-off URL

    @Test func handoffURLRoundTrips() {
        let id = UUID()
        let url = ShareInbox.handoffURL(id: id)
        #expect(url.absoluteString == "nimbus://send?inbox=\(id.uuidString)")
        #expect(ShareInbox.inboxID(from: url) == id)
    }

    @Test func onlyAnInboxIDIsAccepted() {
        let id = UUID().uuidString
        let refused = [
            "nimbus://send?path=/etc/passwd",
            "nimbus://send?inbox=\(id)&path=/etc/passwd",
            "nimbus://send?inbox=not-a-uuid",
            "nimbus://send?inbox=../../etc",
            "nimbus://send/extra?inbox=\(id)",
            "nimbus://other?inbox=\(id)",
            "nimbus://send",
            "https://send?inbox=\(id)",
            "file:///etc/passwd",
        ]
        for text in refused {
            #expect(ShareInbox.inboxID(from: URL(string: text)!) == nil, "accepted \(text)")
        }
    }

    // MARK: Manifest

    @Test func manifestRoundTripsThroughTheContainer() throws {
        let container = try scratch()
        defer { try? FileManager.default.removeItem(at: container) }
        let id = UUID()
        let manifest = ShareInbox.Manifest(items: [
            .init(path: "/Users/me/Documents/report.pdf", staged: false),
            .init(path: "Image.png", staged: true),
        ])
        try ShareInbox.write(manifest, id: id, in: container)
        #expect(try ShareInbox.read(id: id, in: container) == manifest)

        let urls = ShareInbox.fileURLs(of: manifest, id: id, in: container)
        #expect(urls.map(\.path) == [
            "/Users/me/Documents/report.pdf",
            ShareInbox.folder(id: id, in: container).appendingPathComponent("Image.png").path,
        ])
    }

    @Test func aMissingOrNewerManifestIsRefused() throws {
        let container = try scratch()
        defer { try? FileManager.default.removeItem(at: container) }
        #expect(throws: ShareInbox.Problem.missing) { try ShareInbox.read(id: UUID(), in: container) }

        let id = UUID()
        var newer = ShareInbox.Manifest(items: [])
        newer.version = 2
        try ShareInbox.write(newer, id: id, in: container)
        #expect(throws: ShareInbox.Problem.unsupportedVersion) { try ShareInbox.read(id: id, in: container) }
    }

    @Test func stagedItemsCannotClimbOutOfTheirInbox() {
        let container = URL(fileURLWithPath: "/tmp/group")
        let manifest = ShareInbox.Manifest(items: [
            .init(path: "../../../etc/passwd", staged: true),
            .init(path: "/etc/passwd", staged: true),
            .init(path: "..", staged: true),
            .init(path: "", staged: true),
            .init(path: ShareInbox.manifestName, staged: true),
            .init(path: "relative/path.txt", staged: false),
            .init(path: "ok.txt", staged: true),
        ])
        let urls = ShareInbox.fileURLs(of: manifest, id: UUID(), in: container)
        #expect(urls.map(\.lastPathComponent) == ["ok.txt"])
    }

    // MARK: Staging rules

    @Test func filesInOtherAppsContainersAndTempFoldersAreStaged() {
        #expect(ShareInbox.needsStaging(path: "/Users/me/Library/Containers/com.apple.Preview/Data/tmp/a.pdf"))
        #expect(ShareInbox.needsStaging(path: "/Users/me/Library/Group Containers/group.x/a.pdf"))
        #expect(ShareInbox.needsStaging(path: "/private/var/folders/ab/T/a.png"))
        #expect(ShareInbox.needsStaging(path: "/var/folders/ab/T/a.png"))
        #expect(ShareInbox.needsStaging(path: "/tmp/a.png"))
        #expect(!ShareInbox.needsStaging(path: "/Users/me/Documents/a.pdf"))
        #expect(!ShareInbox.needsStaging(path: "/Volumes/DATA/a.pdf"))
    }

    @Test func stagedNamesNeverCollideOrEscape() {
        #expect(ShareInbox.uniqueName("Image.png", taken: []) == "Image.png")
        #expect(ShareInbox.uniqueName("Image.png", taken: ["Image.png"]) == "Image 2.png")
        #expect(ShareInbox.uniqueName("Image.png", taken: ["Image.png", "Image 2.png"]) == "Image 3.png")
        #expect(ShareInbox.uniqueName("Text", taken: ["Text"]) == "Text 2")
        #expect(ShareInbox.uniqueName("a/b.txt", taken: []) == "a-b.txt")
        #expect(ShareInbox.uniqueName("", taken: []) == "Shared Item")
        #expect(ShareInbox.uniqueName(ShareInbox.manifestName, taken: []) == "Shared Item")
    }

    @Test func theCopyCapIsTwoGigabytes() {
        #expect(ShareInbox.stagedByteLimit == 2 * 1024 * 1024 * 1024)
    }

    // MARK: Cleanup

    @Test func sweepRemovesOnlyStaleInboxes() throws {
        let container = try scratch()
        defer { try? FileManager.default.removeItem(at: container) }
        let old = UUID(), fresh = UUID()
        try ShareInbox.write(.init(items: []), id: old, in: container)
        try ShareInbox.write(.init(items: []), id: fresh, in: container)
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        try FileManager.default.setAttributes(
            [.modificationDate: twoDaysAgo], ofItemAtPath: ShareInbox.folder(id: old, in: container).path
        )

        ShareInbox.sweep(in: container)
        #expect(!FileManager.default.fileExists(atPath: ShareInbox.folder(id: old, in: container).path))
        #expect(FileManager.default.fileExists(atPath: ShareInbox.folder(id: fresh, in: container).path))

        ShareInbox.remove(id: fresh, in: container)
        #expect(!FileManager.default.fileExists(atPath: ShareInbox.folder(id: fresh, in: container).path))
    }

    // MARK: App side

    @Test func aHandoffURLBecomesASendRequestForTheInboxFiles() throws {
        let container = try scratch()
        defer { try? FileManager.default.removeItem(at: container) }
        let id = UUID()
        let direct = container.appendingPathComponent("direct.txt")
        try Data("d".utf8).write(to: direct)
        try ShareInbox.write(.init(items: [
            .init(path: direct.path, staged: false),
            .init(path: "Image.png", staged: true),
            .init(path: "gone.txt", staged: true),
        ]), id: id, in: container)
        try Data("i".utf8).write(to: ShareInbox.folder(id: id, in: container).appendingPathComponent("Image.png"))

        let request = try #require(NimbusServicesProvider.request(
            fromHandoff: ShareInbox.handoffURL(id: id), container: container
        ))
        #expect(request.items.map(\.name) == ["direct.txt", "Image.png"])
        #expect(request.inboxID == id)
    }

    @Test func aHandoffURLForNothingIsIgnored() throws {
        let container = try scratch()
        defer { try? FileManager.default.removeItem(at: container) }
        #expect(NimbusServicesProvider.request(fromHandoff: ShareInbox.handoffURL(id: UUID()), container: container) == nil)
        #expect(NimbusServicesProvider.request(
            fromHandoff: URL(string: "nimbus://send?path=/etc/passwd")!, container: container
        ) == nil)
        #expect(NimbusServicesProvider.request(fromHandoff: ShareInbox.handoffURL(id: UUID()), container: nil) == nil)
    }
}
