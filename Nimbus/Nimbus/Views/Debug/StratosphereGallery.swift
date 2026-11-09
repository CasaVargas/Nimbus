#if DEBUG
import SwiftUI

/// Every Stratosphere building block on one page, for judging the look
/// before any real screen uses it. DEBUG only: open it from the Window menu
/// or use the previews below.
struct StratosphereGalleryScene: Scene {
    var body: some Scene {
        Window("Stratosphere Gallery", id: "stratosphere-gallery") {
            StratosphereGallery()
        }
        .windowResizability(.contentSize)
    }
}

struct StratosphereGallery: View {
    @Environment(\.stratosphere) private var palette

    private typealias S = DesignSystem.Stratosphere

    private struct Cloud: Identifiable {
        let id: String
        let provider: String
        let status: StratosphereStatus
        let statusText: String
        let used: String
        let fraction: Double?
        let share: Double
    }

    private let clouds: [Cloud] = [
        .init(id: "Personal", provider: "drive", status: .ok, statusText: "Ready", used: "1.28 of 2 TB", fraction: 0.64, share: 0.224),
        .init(id: "Work", provider: "onedrive", status: .warning, statusText: "Needs sign-in", used: "412 GB of 1 TB", fraction: 0.41, share: 0.072),
        .init(id: "Dropbox", provider: "dropbox", status: .ok, statusText: "Uploading 3 items", used: "61 GB of 2 TB", fraction: 0.03, share: 0.011),
        .init(id: "Photo Archive", provider: "b2", status: .ok, statusText: "Ready", used: "720 GB, billed by use", fraction: nil, share: 0.126),
    ]

    private var colors: [String: S.CloudColor] {
        S.CloudColors.assign(clouds.map { (name: $0.id, provider: $0.provider) })
    }

    var body: some View {
        ZStack {
            StratosphereBackdrop()
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                hero
                cards
                controls
            }
            .padding(DesignSystem.Spacing.xxl)
        }
        .frame(width: 920, height: 640)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.xxl) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
                Text("All your clouds")
                    .font(S.Typography.label)
                    .foregroundStyle(palette.textSecondary.color)
                Text("3.25 TB free")
                    .font(S.Typography.hero)
                    .foregroundStyle(palette.textPrimary.color)
                Text("2.47 TB used across 5 clouds. Four are in sync. Work is waiting for you to sign in.")
                    .font(S.Typography.lead)
                    .foregroundStyle(palette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380, alignment: .leading)
                Button { } label: { Label("Add Cloud", systemImage: "plus") }
                    .buttonStyle(.primaryPill)
            }
            Spacer(minLength: 0)
            StorageRing(
                segments: clouds.map { .init(id: $0.id, fraction: $0.share, color: colors[$0.id] ?? S.CloudColors.sequence[0]) },
                accessibilityLabel: Text("2.47 TB of 5.72 TB used")
            ) {
                VStack(spacing: 2) {
                    Text("43%")
                        .font(S.Typography.ringValue)
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary.color)
                    Text("2.47 of 5.72 TB used")
                        .font(S.Typography.detail)
                        .foregroundStyle(palette.textSecondary.color)
                }
            }
            .frame(width: 204, height: 204)
        }
    }

    private var cards: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            ForEach(clouds) { cloud in
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                    LogoTile(provider: cloud.provider)
                    Text(verbatim: cloud.id)
                        .font(S.Typography.sectionTitle)
                        .foregroundStyle(palette.textPrimary.color)
                    HStack(spacing: 6) {
                        StatusDot(status: cloud.status)
                        Text(verbatim: cloud.statusText)
                            .font(S.Typography.detail)
                            .foregroundStyle(palette.textSecondary.color)
                    }
                    Spacer(minLength: 0)
                    if let fraction = cloud.fraction, let color = colors[cloud.id] {
                        UsageBar(fraction: fraction, color: color)
                    }
                    Text(verbatim: cloud.used)
                        .font(S.Typography.detail)
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary.color)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 170, alignment: .leading)
                .glassSurface()
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            HStack(spacing: DesignSystem.Spacing.m) {
                Button("Sign In to OneDrive") { }.buttonStyle(.primaryPill(.small))
                Button("Copy To…") { }.buttonStyle(.glassCapsule)
                Button { } label: { Image(systemName: "ellipsis") }
                    .buttonStyle(.glassCapsule)
                    .accessibilityLabel("More")
                Button("Disabled") { }.buttonStyle(.primaryPill(.small)).disabled(true)
                Spacer(minLength: 0)
            }
            HStack(spacing: DesignSystem.Spacing.s) {
                Chip(text: Text("Ran 6 hours ago"), status: .ok)
                Chip(text: Text("Skipped last night"), status: .warning)
                Chip(text: Text("214 files · 1.2 GB"))
                Spacer(minLength: 0)
                Text("Tertiary text sits at the contrast floor.")
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textTertiary.color)
            }
        }
        .padding(DesignSystem.Spacing.l)
        .glassSurface(radius: S.Radius.header, tint: colors["Personal"])
    }
}

#Preview("Stratosphere, dark") {
    StratosphereGallery().preferredColorScheme(.dark)
}

#Preview("Stratosphere, light") {
    StratosphereGallery().preferredColorScheme(.light)
}
#endif
