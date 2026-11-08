import Foundation
import SwiftUI
import Testing
import RcloneKit
@testable import Nimbus

/// Renders real Nimbus screens (fixture data) at 2x for the launch
/// film. Runs only with TEST_RUNNER_FILM_OUT=<folder>. Copy into Nimbus/NimbusTests/ (on a branch with Backups) and run with TEST_RUNNER_FILM_OUT=<repo>/docs/marketing/launch-film/assets/screens.
@Suite("FilmCapture", .serialized, .enabled(if: ProcessInfo.processInfo.environment["FILM_OUT"] != nil))
@MainActor
struct FilmCaptureTests {
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FILM_OUT"] ?? "/tmp")

    private func save<V: View>(_ view: V, _ size: CGSize, _ name: String) throws {
        let framed = view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let data = SnapshotHelpers.renderHostedPNG(framed, size: size)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try data.write(to: out.appendingPathComponent("\(name).png"))
    }

    private var dropboxReady: CloudSummary.Row {
        HomePreviewData.row("Dropbox", "dropbox", "Dropbox", .ready, "Ready",
                            used: 61 * HomePreviewData.gb, total: 2 * HomePreviewData.tb, tint: 2)
    }

    private var activity: [ActivityLine] {
        [
            .init(id: UUID(), text: "Backed up Documents to Photo Archive", date: Date().addingTimeInterval(-1_800), isFailure: false, cloud: "Photo Archive"),
            .init(id: UUID(), text: "Copied Yosemite 2026 to Personal", date: Date().addingTimeInterval(-7_200), isFailure: false, cloud: "Personal"),
            .init(id: UUID(), text: "Copied Client Work to Dropbox", date: Date().addingTimeInterval(-90_000), isFailure: false, cloud: "Dropbox"),
        ]
    }

    @Test func home() throws {
        let rows = [HomePreviewData.personal, HomePreviewData.workReady, dropboxReady, HomePreviewData.archive]
        try save(HomeContent(summary: HomePreviewData.summary(rows, overall: .allReady), activity: activity, providerCount: 72),
                 CGSize(width: 1100, height: 450), "home")
    }

    @Test func homeBusy() throws {
        let rows = [HomePreviewData.personal, HomePreviewData.workReady, HomePreviewData.dropbox, HomePreviewData.archive]
        let busy = CloudSummary.Overall.busy(.init(progress: 0.42, sentence: "Copying 3 items to Dropbox", direction: .up,
                                                   focusCloud: "Dropbox", eta: 120))
        try save(HomeContent(summary: HomePreviewData.summary(rows, overall: busy), activity: activity, providerCount: 72),
                 CGSize(width: 1100, height: 450), "home-busy")
    }

    @Test func companion() throws {
        let rows = [HomePreviewData.personal, HomePreviewData.workReady, dropboxReady, HomePreviewData.archive]
        try save(CompanionContent(summary: HomePreviewData.summary(rows, overall: .allReady), activity: activity,
                                  openAtLogin: .constant(true)),
                 CGSize(width: CompanionContent.width, height: 520), "companion")
    }

    @Test func backups() throws {
        let docs = TransferEndpoint.local(path: "/Users/you/Documents")
        let running = Transfer(jobID: 1, operation: .sync, srcFs: "a", dstFs: "b", startedAt: BackupsFixtures.now,
                               status: .active, origin: .backup, nimbusUUID: UUID(), progress: 0.62, eta: 95)
        let rows = [
            BackupsFixtures.row(BackupsFixtures.job("Documents to Photo Archive", source: docs,
                                                    destination: .cloud(remote: "Photo Archive", path: "mac/Documents")), running: running),
            BackupsFixtures.row(BackupsFixtures.job("Desktop to Personal", source: .local(path: "/Users/you/Desktop"),
                                                    destination: .cloud(remote: "Personal", path: "Desktop")) {
                $0.lastRun = BackupsFixtures.summary(.completed, copied: 48)
            }, destinationType: "drive"),
            BackupsFixtures.row(BackupsFixtures.job("Photos to Dropbox", source: .local(path: "/Users/you/Pictures"),
                                                    destination: .cloud(remote: "Dropbox", path: "Photos")) {
                $0.lastRun = BackupsFixtures.summary(.completed, copied: 312, hoursAgo: 20)
            }, destinationType: "dropbox"),
        ]
        try save(BackupsContent(rows: rows, loadState: .loaded, actions: .init()), CGSize(width: 900, height: 262), "backups")
    }

    @Test func preview() throws {
        let preview = BackupPreview(
            willCopy: ["Taxes/2026/receipt-0412.pdf", "Taxes/2026/receipt-0418.pdf", "Projects/Nimbus/launch-notes.md",
                       "Projects/Nimbus/storyboard.key", "Photos/2026/Yosemite/IMG_4827.heic", "Photos/2026/Yosemite/IMG_4828.heic",
                       "Photos/2026/Yosemite/IMG_4831.heic", "Letters/thank-you.pages", "Music/Demos/sketch-07.m4a",
                       "Notes/ideas.md", "Recipes/sourdough.pdf", "Travel/itinerary.pdf"],
            willReplace: ["Notes/reading-list.md", "Budget/2026.numbers"],
            willRemove: ["Old/draft-v1.pages"], errors: [], approxBytes: 48_213_004, limitHit: false,
            removalLimit: 100, fingerprint: "f", finishedAt: .now)
        let context = BackupPreviewContent.Context(
            isBackup: true, isMirror: true, versionsDescription: ".nimbus-versions",
            destinationDescription: "Photo Archive › mac/Documents", destinationIsLocal: false,
            removalLimit: 100, startLabel: nil)
        try save(BackupPreviewContent(state: .finished(preview), context: context, actions: .init()),
                 CGSize(width: 640, height: 560), "preview")
    }

    @Test func picker() throws {
        func provider(_ name: String, _ description: String) -> Provider {
            let json = #"{"Name":"\#(name)","Description":"\#(description)","Prefix":"\#(name)","Options":[]}"#
            return try! JSONDecoder().decode(Provider.self, from: Data(json.utf8))
        }
        let providers = [
            provider("drive", "Google Drive"), provider("onedrive", "Microsoft OneDrive"), provider("dropbox", "Dropbox"),
            provider("iclouddrive", "iCloud Drive"), provider("box", "Box"), provider("pcloud", "Pcloud"),
            provider("protondrive", "Proton Drive"), provider("mega", "Mega"),
            provider("s3", "Amazon S3 Compliant Storage Providers"), provider("b2", "Backblaze B2"),
            provider("sftp", "SSH/SFTP"), provider("webdav", "WebDAV"), provider("ftp", "FTP"),
        ] + ["Akamai NetStorage", "Alias", "Azure Blob", "Azure Files", "Cache", "Chunker", "Citrix ShareFile",
             "Cloudinary", "Combine", "Compress", "Encrypt/Decrypt", "Enterprise File Fabric", "Files.com", "Filen",
             "Gofile", "Google Cloud Storage", "Google Photos", "Hasher", "HDFS", "HiDrive", "HTTP", "iCloud Photos",
             "ImageKit", "Internet Archive", "Jottacloud", "Koofr", "Linkbox", "Local Disk", "Mail.ru Cloud",
             "Memory", "Microsoft SharePoint", "NetStorage", "OpenDrive", "OpenStack Swift", "Oracle Object Storage",
             "PikPak", "Pixeldrain", "Premiumize", "put.io", "Quatrix", "Seafile", "Sia", "SMB / CIFS", "Storj",
             "SugarSync", "Ulozto", "Union", "Uptobox", "Yandex Disk", "Zoho WorkDrive", "Dropbox Business",
             "Box Enterprise", "Hetzner Storage Box", "IDrive e2", "Wasabi", "Cloudflare R2", "DigitalOcean Spaces",
             "MinIO", "Ceph"].map { provider($0.lowercased().filter { $0.isLetter || $0.isNumber }, $0) }
        let sheet = SheetChrome(title: "Add Cloud", subtitle: nil, body: {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                SetupSteps(titles: ["Choose a service", "Name it", "Sign in"], current: 0)
                ProviderPicker(providers: providers, onPick: { _ in }, onImport: {})
            }
        }, actions: { Button("Cancel") {} })
        try save(sheet, CGSize(width: 600, height: 700), "picker")
    }
}
