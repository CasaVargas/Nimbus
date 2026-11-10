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
#endif
