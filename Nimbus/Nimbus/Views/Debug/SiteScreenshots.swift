#if DEBUG
import SwiftUI
import RcloneKit

// Previews that produce the website's and README's screenshots: the real
// views with demo data, drawn at twice their size so the images are sharp
// on a Retina display even when rendered on a 1x Mac. Render each with
// Xcode's preview snapshot and copy the PNG to docs/screenshots and
// site/assets under the name in the preview's title.

/// Draws `content` at `width` x `height` points, scaled 2x.
private struct SiteShot<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: width, height: height)
            .scaleEffect(2, anchor: .topLeading)
            .frame(width: width * 2, height: height * 2, alignment: .topLeading)
    }
}

private enum SiteData {
    static let homeRows = [HomePreviewData.personal, HomePreviewData.work, HomePreviewData.dropbox,
                           HomePreviewData.archive, HomePreviewData.nas]

    static var homeSummary: CloudSummary {
        HomePreviewData.summary(homeRows, overall: .needsAttention(HomePreviewData.work), attention: HomePreviewData.work,
                                suggestions: [.notInFinder(HomePreviewData.archive)])
    }

    static var readySummary: CloudSummary {
        HomePreviewData.summary([HomePreviewData.personal, HomePreviewData.workReady, HomePreviewData.archive],
                                overall: .allReady)
    }

    static func provider(_ name: String, _ description: String) -> Provider {
        let json = #"{"Name":"\#(name)","Description":"\#(description)","Prefix":"\#(name)","Options":[]}"#
        return try! JSONDecoder().decode(Provider.self, from: Data(json.utf8))
    }

    static let providers: [Provider] = [
        provider("drive", "Google Drive"), provider("onedrive", "Microsoft OneDrive"), provider("dropbox", "Dropbox"),
        provider("iclouddrive", "iCloud Drive"), provider("box", "Box"), provider("pcloud", "Pcloud"),
        provider("protondrive", "Proton Drive"), provider("mega", "Mega"),
        provider("s3", "Amazon S3 Compliant Storage Providers"), provider("b2", "Backblaze B2"),
        provider("sftp", "SSH/SFTP"), provider("webdav", "WebDAV"),
        provider("crypt", "Encrypt/Decrypt a remote"), provider("ftp", "FTP"),
    ] + [provider("netstorage", "Akamai NetStorage"), provider("alias", "Alias for an existing remote"),
         provider("azureblob", "Microsoft Azure Blob Storage")] + moreBackends.map { provider($0, $0) }

    /// Real rclone backend names, so the picker's count reads like the
    /// shipping app's rather than like a fixture's.
    private static let moreBackends = [
        "azurefiles", "gcs", "gphotos", "sharefile", "swift", "hdfs", "smb", "http", "storj",
        "seafile", "sia", "sugarsync", "yandex", "zoho", "koofr", "jottacloud", "hidrive", "mailru", "opendrive",
        "pikpak", "premiumizeme", "putio", "quatrix", "linkbox", "fichier", "filefabric", "filescom", "gofile",
        "internetarchive", "oracleobjectstorage", "pixeldrain", "qingstor", "ulozto", "uptobox",
        "imagekit", "cloudinary", "combine", "union", "compress", "chunker", "hasher", "cache", "local", "memory",
        "tardigrade", "iclouddphotos", "onedrivebusiness", "sharepoint", "wasabi", "r2", "minio", "digitalocean",
        "linode", "scaleway", "idrive", "storadera",
    ]

    static var driveQuestion: ConfigQuestion {
        let json = #"""
        {"Name": "config_change_team_drive", "Help": "Configure this as a Shared Drive (Team Drive)?\n", "Type": "bool",
         "Required": false, "IsPassword": false, "Advanced": false, "Sensitive": false, "Hide": 0, "Exclusive": true,
         "Default": false, "DefaultStr": "false", "Value": null,
         "Examples": [{"Value": "true", "Help": "Yes"}, {"Value": "false", "Help": "No"}]}
        """#
        return ConfigQuestion(option: try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8)),
                              state: "teamdrive_ok")
    }

    static var backupRows: [BackupsContent.Row] {
        let now = BackupsFixtures.now
        let documents = TransferEndpoint.local(path: "/Users/you/Documents")
        let running = Transfer(jobID: 1, operation: .sync, srcFs: "a", dstFs: "b", startedAt: now, status: .active,
                               origin: .backup, nimbusUUID: UUID(), progress: 0.45, eta: 180)
        return [
            BackupsFixtures.row(BackupsFixtures.job("Documents to Photo Archive", source: documents,
                                                    destination: .cloud(remote: "Photo Archive", path: "mac/Documents")),
                                running: running),
            BackupsFixtures.row(BackupsFixtures.job("Desktop to Personal", source: .local(path: "/Users/you/Desktop"),
                                                    destination: .cloud(remote: "Personal", path: "Mac/Desktop")) {
                $0.lastRun = BackupsFixtures.summary(.completed, copied: 38, hoursAgo: 3)
            }, destinationType: "drive"),
            BackupsFixtures.row(BackupsFixtures.job("Projects to Photo Archive", source: .local(path: "/Users/you/Projects"),
                                                    destination: .cloud(remote: "Photo Archive", path: "projects")) {
                $0.lastRun = BackupsFixtures.summary(.completed, copied: 214, hoursAgo: 26)
            }),
            BackupsFixtures.row(BackupsFixtures.job("Lightroom Catalog to Dropbox", source: .local(path: "/Users/you/Pictures/Lightroom"),
                                                    destination: .cloud(remote: "Dropbox", path: "Lightroom"), approved: false),
                                destinationType: "dropbox"),
        ]
    }
}

#Preview("window-home", traits: .fixedLayout(width: 2560, height: 1600)) {
    SiteShot(width: 1280, height: 800) {
        DemoWindow(title: "Home", selection: .home) {
            HomeContent(summary: SiteData.homeSummary, activity: HomePreviewData.activity, providerCount: 72)
        }
    }
}

#Preview("home-light", traits: .fixedLayout(width: 2000, height: 1240)) {
    SiteShot(width: 1000, height: 620) {
        HomeContent(summary: SiteData.readySummary, activity: HomePreviewData.activity, providerCount: 72)
            .background { StratosphereBackdrop() }
    }
    .preferredColorScheme(.light)
}

#Preview("window-files", traits: .fixedLayout(width: 2560, height: 1600)) {
    @Previewable @State var tab: VolumeTab = .files
    @Previewable @State var sortField: SortField = .name
    @Previewable @State var sortAscending = true
    SiteShot(width: 1280, height: 800) {
        DemoWindow(title: "Personal", selection: .remote("Personal")) {
            VolumePaneLayout {
                VolumeHeader(remote: Remote(name: "Personal", type: "drive", config: [:]), providerName: "Google Drive",
                             quota: StorageQuota(used: 1_280_000_000_000, total: 2_000_000_000_000), status: .connected,
                             isInFinder: true, onPrimary: {}, onSync: {}, onEdit: {})
                VolumeTabBar(selection: $tab)
                VStack(spacing: 0) {
                    FileTableHeader(sortField: $sortField, sortAscending: $sortAscending)
                    Divider()
                    VStack(spacing: 0) {
                        ForEach(DemoWindow<EmptyView>.files) { file in
                            FileRowView(file: file, remote: "Personal", isSelected: file.name == "Lease.pdf")
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(file.name == "Lease.pdf" ? Color(nsColor: .selectedContentBackgroundColor) : .clear)
                                )
                                .padding(.horizontal, 10)
                        }
                    }
                    .padding(.top, DesignSystem.Spacing.xs)
                    Spacer(minLength: 0)
                }
                .glassContentSurface()
            }
        }
    }
}

#Preview("window-backups", traits: .fixedLayout(width: 2560, height: 1600)) {
    SiteShot(width: 1280, height: 800) {
        DemoWindow(title: "Backups", selection: .backups) {
            BackupsContent(rows: SiteData.backupRows, loadState: .loaded, actions: .init())
        }
    }
}

#Preview("add-cloud", traits: .fixedLayout(width: 1200, height: 1520)) {
    SiteShot(width: 600, height: 760) {
        SheetChrome(title: "Add Cloud", subtitle: nil, body: {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                SetupSteps(titles: ["Choose a service", "Name it", "Sign in"], current: 0)
                ProviderPicker(providers: SiteData.providers, onPick: { _ in }, onImport: {})
            }
        }, actions: {
            Button("Cancel") {}.buttonStyle(.glassCapsule)
        })
    }
    .preferredColorScheme(.dark)
}

#Preview("add-cloud-question", traits: .fixedLayout(width: 1200, height: 1040)) {
    @Previewable @State var value = "false"
    SiteShot(width: 600, height: 520) {
        SheetChrome(title: "Add Cloud", subtitle: nil, body: {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                SetupSteps(titles: ["Choose a service", "Name it", "Sign in"], current: 2)
                FollowUpQuestion(providerPrefix: "drive", question: SiteData.driveQuestion, value: value,
                                 onChange: { value = $0 })
            }
        }, actions: {
            Button("Cancel") {}.buttonStyle(.glassCapsule)
            Button("Continue") {}.buttonStyle(.primaryPill(.small))
        })
    }
    .preferredColorScheme(.dark)
}

#Preview("companion-busy", traits: .fixedLayout(width: 680, height: 1100)) {
    @Previewable @State var openAtLogin = true
    SiteShot(width: 340, height: 550) {
        CompanionContent(
            summary: HomePreviewData.summary(
                [HomePreviewData.personal, HomePreviewData.workReady, HomePreviewData.dropbox,
                 HomePreviewData.archive, HomePreviewData.nas],
                overall: .busy(.init(progress: 0.34, sentence: "Copying 3 items to Dropbox", direction: .up,
                                     focusCloud: "Dropbox", eta: 130))),
            activity: HomePreviewData.activity, openAtLogin: $openAtLogin)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(DesignSystem.Stratosphere.Palette.dark.sheetBottom.color)
    }
    .preferredColorScheme(.dark)
}

#Preview("companion-sign-in", traits: .fixedLayout(width: 680, height: 1000)) {
    @Previewable @State var openAtLogin = true
    SiteShot(width: 340, height: 500) {
        CompanionContent(
            summary: HomePreviewData.summary(
                [HomePreviewData.personal, HomePreviewData.work, HomePreviewData.archive, HomePreviewData.nas],
                overall: .needsAttention(HomePreviewData.work), attention: HomePreviewData.work),
            activity: HomePreviewData.activity, openAtLogin: $openAtLogin)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(DesignSystem.Stratosphere.Palette.dark.sheetBottom.color)
    }
    .preferredColorScheme(.dark)
}

#Preview("onboarding", traits: .fixedLayout(width: 1640, height: 1400)) {
    SiteShot(width: 820, height: 700) {
        OnboardingView()
            .environment(AppSettings(defaults: UserDefaults(suiteName: "SiteScreenshots")!))
            .environment(RcloneDaemon())
            .environment(MountConfigStore())
            .environment(MountManager())
            .environment(FileProviderBridge())
    }
    .preferredColorScheme(.dark)
}

// MARK: - 1.0 features

private enum SiteFiles {
    static func file(_ remote: String, _ path: String, size: Int64 = 1_400_000, daysAgo: Double = 12) -> FileItem {
        FileItem(path: path, name: (path as NSString).lastPathComponent, size: size, mimeType: "application/pdf",
                 modTime: Date().addingTimeInterval(-daysAgo * 86_400), isDir: false, fileID: nil,
                 qualifiedRemotePath: "\(remote):\(path)")
    }
}

#Preview("search", traits: .fixedLayout(width: 1640, height: 1000)) {
    let clouds = [
        CloudSearchResult(remote: "Personal", providerType: "drive", phase: .done,
                          items: [SiteFiles.file("Personal", "Documents/Home/Lease.pdf"),
                                  SiteFiles.file("Personal", "Documents/Home/Lease renewal 2026.pdf", size: 620_000, daysAgo: 3)],
                          total: 2),
        CloudSearchResult(remote: "Dropbox", providerType: "dropbox", phase: .done,
                          items: [SiteFiles.file("Dropbox", "Scans/Lease, signed.pdf", size: 2_900_000, daysAgo: 40)], total: 1),
        CloudSearchResult(remote: "Photo Archive", providerType: "b2", phase: .searching),
        CloudSearchResult(remote: "Work", providerType: "onedrive", phase: .failed("Sign in again to search this cloud.")),
    ]
    SiteShot(width: 820, height: 500) {
        List {
            ForEach(clouds) { cloud in
                Section {
                    ForEach(cloud.items, id: \.qualifiedRemotePath) { SearchResultRow(file: $0) }
                } header: {
                    SearchSectionHeader(cloud: cloud)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { StratosphereBackdrop() }
    }
    .preferredColorScheme(.dark)
}

#Preview("compare", traits: .fixedLayout(width: 1720, height: 1120)) {
    SiteShot(width: 860, height: 560) {
        CompareResultsView(
            result: CompareResult(combined: [
                "= Photos/2024/beach.jpg", "= Photos/2024/hike.jpg", "= Notes.md", "= Recipes.pdf",
                "* Taxes/2025 return.pdf", "* Budget 2026.xlsx",
                "+ Projects/Kitchen/plan.pdf", "+ Projects/Kitchen/quote.pdf", "+ Inbox/receipt.png",
                "- Old/archive.zip",
            ]),
            nameA: "Documents", nameB: "Personal: Backup/Documents"
        )
        .padding(DesignSystem.Spacing.xl)
        .background { StratosphereBackdrop() }
    }
    .preferredColorScheme(.dark)
}

// The sheet's own width, and a height that leaves the list at its minimum:
// the picture is the sheet edge to edge, padding included, with no rows of
// nothing under the three versions.
#Preview("versions", traits: .fixedLayout(width: 880, height: 620)) {
    let now = Date()
    SiteShot(width: 440, height: 310) {
        FileVersionsSheet(remote: "Photo Archive",
                          file: SiteFiles.file("Photo Archive", "projects/Deck.key", size: 48_000_000, daysAgo: 0),
                          versionsOverride: [
            FileVersion(path: "a", name: "a", savedAt: now.addingTimeInterval(-3_600), size: 47_600_000),
            FileVersion(path: "b", name: "b", savedAt: now.addingTimeInterval(-86_400 * 2), size: 44_100_000),
            FileVersion(path: "c", name: "c", savedAt: now.addingTimeInterval(-86_400 * 30), size: 12_800_000),
        ])
        .environment(RcloneDaemon())
        .environment(TransferStore())
    }
    .preferredColorScheme(.dark)
}

#Preview("backup-editor", traits: .fixedLayout(width: 1200, height: 1280)) {
    SiteShot(width: 600, height: 640) {
        BackupEditorSheet(
            original: BackupsFixtures.job("Documents to Photo Archive", source: .local(path: "/Users/you/Documents"),
                                          destination: .cloud(remote: "Photo Archive", path: "mac/Documents")) {
                $0.schedule = .weekly(weekday: 6, hour: 21, minute: 30)
            },
            remoteNames: ["Photo Archive", "Personal"], client: RcloneClient(), onSave: { _, _ in })
            .environment(LaunchAtLoginService(refreshOnInit: false))
            .environment(BackgroundBackupsService(refreshOnInit: false))
    }
    .preferredColorScheme(.dark)
}

#Preview("backup-preview", traits: .fixedLayout(width: 1360, height: 1160)) {
    SiteShot(width: 680, height: 580) {
        BackupPreviewContent(
            state: .finished(BackupPreview(
                willCopy: (1...12).map { "Taxes/2026/receipt-\($0).pdf" },
                willReplace: ["Notes/Kitchen.md", "Budget 2026.xlsx"], willRemove: ["Old/draft.txt"],
                errors: [], approxBytes: 48_213_004, limitHit: false, removalLimit: 100,
                fingerprint: "f", finishedAt: .now)),
            context: .init(isBackup: true, isMirror: true, versionsDescription: ".nimbus-versions",
                           destinationDescription: "Photo Archive › mac/Documents", destinationIsLocal: false,
                           removalLimit: 100, startLabel: nil),
            actions: .init())
    }
    .preferredColorScheme(.dark)
}

#Preview("home-ready", traits: .fixedLayout(width: 2000, height: 1240)) {
    SiteShot(width: 1000, height: 620) {
        HomeContent(summary: SiteData.readySummary, activity: HomePreviewData.activity, providerCount: 72)
            .background { StratosphereBackdrop() }
    }
    .preferredColorScheme(.dark)
}

#Preview("encrypted-folder", traits: .fixedLayout(width: 1120, height: 1480)) {
    let client = RcloneClient()
    let setup = EncryptedFolderSetup(client: client, existingNames: ["Personal", "Work", "Dropbox"])
    setup.folder = .cloud(remote: "Personal", path: "Private")
    setup.nameDraft = "Private"
    setup.password = "demo-password-only"
    setup.confirmation = "demo-password-only"
    setup.acknowledged = true
    return SiteShot(width: 560, height: 740) {
        EncryptedFolderSheet(client: client, remoteNames: ["Personal", "Work", "Dropbox"], setup: setup, onDismiss: {})
            .environment(AppSettings(defaults: UserDefaults(suiteName: "SiteScreenshots")!))
            .environment(FileProviderBridge())
    }
    .preferredColorScheme(.dark)
}

// MARK: - 1.4 features

/// Stand-in pictures for the gallery shot, drawn here so no real photo or
/// document is ever in a screenshot: a sky, a sun and hills for photos, a
/// ruled page for PDFs.
private struct SiteDemoThumbnails: GalleryThumbnailProviding {
    func cachedImage(for request: ThumbnailRequest) -> CGImage? {
        switch request.kind {
        case .image: Self.landscape(seed: request.name, width: request.maxPixel, height: request.maxPixel * 2 / 3)
        case .pdf: Self.page(width: request.maxPixel * 17 / 22, height: request.maxPixel)
        case nil: nil
        }
    }

    func image(for request: ThumbnailRequest) async -> CGImage? {
        cachedImage(for: request)
    }

    private static let palettes: [(top: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat),
                                   hill: (CGFloat, CGFloat, CGFloat))] = [
        ((0.16, 0.32, 0.62), (0.98, 0.72, 0.45), (0.10, 0.22, 0.30)),
        ((0.35, 0.62, 0.90), (0.86, 0.94, 0.98), (0.16, 0.42, 0.34)),
        ((0.42, 0.24, 0.52), (0.99, 0.60, 0.50), (0.20, 0.14, 0.30)),
        ((0.10, 0.45, 0.62), (0.70, 0.90, 0.86), (0.86, 0.74, 0.52)),
        ((0.92, 0.55, 0.30), (0.99, 0.88, 0.62), (0.45, 0.24, 0.20)),
    ]

    private static func context(_ width: Int, _ height: Int) -> CGContext? {
        CGContext(data: nil, width: max(width, 1), height: max(height, 1), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func landscape(seed: String, width: Int, height: Int) -> CGImage? {
        guard let context = context(width, height) else { return nil }
        // Constants chosen so the demo folder's names spread over every
        // palette with no two neighbours alike.
        let pick = seed.unicodeScalars.reduce(7) { ($0 &* 21 &+ Int($1.value)) % 104_729 }
        let palette = palettes[(pick / 11) % palettes.count]
        let w = CGFloat(width), h = CGFloat(height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let sky = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: palette.bottom.0, green: palette.bottom.1, blue: palette.bottom.2, alpha: 1),
            CGColor(srgbRed: palette.top.0, green: palette.top.1, blue: palette.top.2, alpha: 1),
        ] as CFArray, locations: [0.25, 1])!
        context.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: h), options: [])

        // Sun.
        let sunX = w * (0.25 + CGFloat(pick % 5) * 0.12), sunY = h * (0.52 + CGFloat(pick % 3) * 0.08)
        let radius = h * 0.09
        context.setFillColor(CGColor(srgbRed: 1, green: 0.96, blue: 0.84, alpha: 0.95))
        context.fillEllipse(in: CGRect(x: sunX - radius, y: sunY - radius, width: radius * 2, height: radius * 2))

        // Three ridges, nearer ones darker.
        for layer in 0..<3 {
            let depth = CGFloat(layer) / 2
            let base = h * (0.46 - depth * 0.16)
            let amplitude = h * (0.10 - depth * 0.02)
            let phase = CGFloat(pick % 7) + CGFloat(layer) * 1.7
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            var x: CGFloat = 0
            while x <= w {
                let t = x / w * 2 * .pi
                let y = base + sin(t * (1.1 + depth) + phase) * amplitude + sin(t * 2.7 + phase * 2) * amplitude * 0.35
                path.addLine(to: CGPoint(x: x, y: y))
                x += max(w / 160, 1)
            }
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            let shade = 0.55 + depth * 0.45
            context.setFillColor(CGColor(srgbRed: palette.hill.0 * (1.6 - shade * 0.6),
                                         green: palette.hill.1 * (1.6 - shade * 0.6),
                                         blue: palette.hill.2 * (1.6 - shade * 0.6), alpha: 1))
            context.addPath(path)
            context.fillPath()
        }
        return context.makeImage()
    }

    private static func page(width: Int, height: Int) -> CGImage? {
        guard let context = context(width, height) else { return nil }
        let w = CGFloat(width), h = CGFloat(height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // A heading and ruled lines: reads as a document, says nothing.
        context.setFillColor(CGColor(gray: 0.25, alpha: 1))
        context.fill(CGRect(x: w * 0.12, y: h * 0.86, width: w * 0.46, height: h * 0.028))
        context.setFillColor(CGColor(gray: 0.78, alpha: 1))
        var y = h * 0.78
        var line = 0
        while y > h * 0.14 {
            let length: CGFloat = line % 5 == 4 ? 0.42 : 0.76
            context.fill(CGRect(x: w * 0.12, y: y, width: w * length, height: h * 0.012))
            y -= h * 0.045
            line += 1
        }
        return context.makeImage()
    }
}

private enum SiteGallery {
    static var files: [FileItem] {
        func item(_ name: String, _ size: Int64, dir: Bool = false, ago: Double) -> FileItem {
            FileItem(path: name, name: name, size: dir ? -1 : size, mimeType: "",
                     modTime: Date().addingTimeInterval(-ago * 86_400), isDir: dir, fileID: nil,
                     qualifiedRemotePath: "Personal:Photos/Yosemite 2026/\(name)")
        }
        return [
            item("Edits", 0, dir: true, ago: 2),
            item("Valley at dawn.heic", 8_400_000, ago: 18),
            item("Half Dome.heic", 7_900_000, ago: 18),
            item("Meadow.heic", 6_200_000, ago: 18),
            item("Tunnel View.heic", 9_100_000, ago: 17),
            item("Mirror Lake.heic", 7_300_000, ago: 17),
            item("Trail map.pdf", 2_100_000, ago: 21),
            item("Glacier Point.heic", 8_800_000, ago: 16),
            item("Campfire.mov", 184_000_000, ago: 16),
            item("Sunset.heic", 6_900_000, ago: 16),
            item("Permit.pdf", 310_000, ago: 30),
            item("Road out.heic", 5_400_000, ago: 15),
        ]
    }
}

#Preview("window-gallery", traits: .fixedLayout(width: 2560, height: 1600)) {
    @Previewable @State var tab: VolumeTab = .files
    let files = SiteGallery.files
    let selection = Selection<String>()
    selection.select(files[4].id, in: files.map(\.id))
    return SiteShot(width: 1280, height: 800) {
        DemoWindow(title: "Personal", selection: .remote("Personal")) {
            VolumePaneLayout {
                VolumeHeader(remote: Remote(name: "Personal", type: "drive", config: [:]), providerName: "Google Drive",
                             quota: StorageQuota(used: 1_280_000_000_000, total: 2_000_000_000_000), status: .connected,
                             isInFinder: true, onPrimary: {}, onSync: {}, onEdit: {})
                VolumeTabBar(selection: $tab)
                FileGallery(files: files, remote: "Personal", selection: selection,
                            thumbnails: SiteDemoThumbnails(),
                            onOpen: { _ in }, onContextAction: { _, _ in }, onQuickLook: { _ in })
                    .glassContentSurface()
            }
        }
    }
}

#Preview("send-to-nimbus", traits: .fixedLayout(width: 960, height: 460)) {
    let request = SendRequest(items: [
        .init(url: URL(fileURLWithPath: "/Users/demo/Desktop/Quarterly report.pdf"), isDirectory: false, size: 9_400_000),
        .init(url: URL(fileURLWithPath: "/Users/demo/Desktop/Floor plan.png"), isDirectory: false, size: 3_100_000),
        .init(url: URL(fileURLWithPath: "/Users/demo/Desktop/Notes.txt"), isDirectory: false, size: 1_700_000),
    ])
    return SiteShot(width: 480, height: 230) {
        SendToNimbusSheet(request: request, remoteNames: ["Personal", "Work", "Dropbox"],
                          lastRemote: "Personal", lastPath: "Inbox", client: RcloneClient(),
                          onAddCloud: {}, onSent: { _, _ in })
            .environment(TransferStore())
    }
    .preferredColorScheme(.dark)
}

#Preview("own-google-sign-in", traits: .fixedLayout(width: 1120, height: 1170)) {
    SiteShot(width: 560, height: 585) {
        OwnClientIDSheet(cloudName: "Personal", client: RcloneClient(), onSaved: { _ in })
    }
    .preferredColorScheme(.dark)
}
#endif
