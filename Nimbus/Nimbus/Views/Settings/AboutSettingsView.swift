import SwiftUI

/// Settings > About: what this is, and the two apps that pay for it.
struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                AboutSettingsSection()
                StudioAppsSection()
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.top)
        .accessibilityIdentifier("settings-about")
    }
}

struct AboutSettingsSection: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    /// The build number tracks the version since #100, so it is shown only
    /// when it says something more.
    private var versionLine: String {
        build == version ? String(localized: "Version \(version)") : String(localized: "Version \(version) (\(build))")
    }

    var body: some View {
        FormSection(title: "About", footer: nil) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.m) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nimbus")
                        .font(DesignSystem.Typography.headline)
                    Text(versionLine)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                        .textSelection(.enabled)
                    Text("© 2026 CasaVargas LLC")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                }
                Spacer()
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
            HStack(spacing: DesignSystem.Spacing.l) {
                Link("Website", destination: URL(string: "https://casavargas.app")!)
                Link("Source Code", destination: URL(string: "https://github.com/CasaVargas/Nimbus")!)
                Link("License", destination: URL(string: "https://github.com/CasaVargas/Nimbus/blob/main/LICENSE")!)
                Spacer()
                Link("Built on rclone", destination: URL(string: "https://rclone.org/")!)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
            .font(DesignSystem.Typography.caption)
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }
}

/// One of Casa Vargas's paid apps, as shown in About.
struct StudioApp: Identifiable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let model: String
    let buttonTitle: String
    let imageName: String
    let url: URL

    static let all: [StudioApp] = [
        StudioApp(
            id: "beltr", name: "Beltr",
            tagline: "Karaoke from the music you already own, on your TV.",
            model: "Bought once, yours to keep.",
            buttonTitle: "See Beltr", imageName: "BeltrIcon",
            url: URL(string: "https://beltr.app/?utm_source=nimbus-app&utm_medium=about&utm_campaign=nimbus")!
        ),
        StudioApp(
            id: "onescribe", name: "OneScribe",
            tagline: "A scanner for iPhone and iPad that reads what it scans.",
            model: "Free to try, Pro bought once.",
            buttonTitle: "View in the App Store", imageName: "OneScribeIcon",
            url: URL(string: "https://apps.apple.com/us/app/onescribe-ai-note-scanner/id6756506734")!
        ),
    ]
}

/// "Nimbus is free. These two pay for it.": a card per app, large enough
/// to be seen. This replaced a single caption-sized row of links.
struct StudioAppsSection: View {
    var body: some View {
        FormSection(
            title: "Nimbus is free. These two pay for it.",
            footer: "Nimbus costs nothing and never will. If it's useful to you, these are how to say thanks."
        ) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.m) {
                ForEach(StudioApp.all) { app in
                    StudioAppCard(app: app)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }
}

struct StudioAppCard: View {
    let app: StudioApp
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            HStack(spacing: DesignSystem.Spacing.m) {
                Image(app.imageName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                Text(verbatim: app.name)
                    .font(DesignSystem.Typography.titleEmphasized)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
            }
            Text(verbatim: app.tagline)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: app.model)
                .font(DesignSystem.Typography.callout)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Spacer(minLength: 0)
            Button(app.buttonTitle) { openURL(app.url) }
                .buttonStyle(.primaryPill(.small))
        }
        .padding(DesignSystem.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.surfaceSubtle)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AboutSettingsView()
        .frame(width: 720, height: 520)
}
