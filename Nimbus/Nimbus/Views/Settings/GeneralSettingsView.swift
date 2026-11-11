import AppKit
import SwiftUI

/// Everyday preferences: how Nimbus starts and looks, what happens to clouds
/// you add later, and About. Network-drive defaults and troubleshooting live
/// in Advanced.
struct GeneralSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                ApplicationSettingsSection()
                NewCloudsSection()
                UpdatesSection()
                AboutSettingsSection()
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.top)
        .accessibilityIdentifier("settings-general")
    }
}

private struct ApplicationSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    var body: some View {
        @Bindable var settings = settings

        FormSection(title: "Nimbus", footer: nil) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                FormRow(label: "Open at Login", help: nil) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel("Open at Login")
                }
                if let error = launchAtLogin.lastError {
                    Text(verbatim: error)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.statusError)
                        .accessibilityLabel("Open at Login error: \(error)")
                }
            }
            RunBackupsWhenClosedRow()
            FormRow(label: "Appearance", help: nil) {
                Picker("Appearance", selection: $settings.appearance) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 120, alignment: .trailing)
                .accessibilityLabel("Appearance")
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { isEnabled in
                if isEnabled {
                    launchAtLogin.register()
                } else {
                    Task { await launchAtLogin.unregister() }
                }
            }
        )
    }
}

/// Run Backups When Nimbus Is Closed (#72): registers the backups agent.
private struct RunBackupsWhenClosedRow: View {
    @Environment(BackgroundBackupsService.self) private var backgroundBackups

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            FormRow(label: LocalizedStringKey(OpenAtLoginNote.runsWhenClosedLabel),
                    help: "Every 15 minutes, if Nimbus is closed, it opens in the background, runs any backups that are due, then quits.") {
                Toggle("", isOn: backgroundBackups.enabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(OpenAtLoginNote.runsWhenClosedLabel)
            }
            if backgroundBackups.needsApproval {
                HStack(spacing: DesignSystem.Spacing.s) {
                    Text("Allow Nimbus in Login Items so backups can run while it's closed.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    Button("Open Login Items") { backgroundBackups.openLoginItems() }
                        .controlSize(.small)
                }
            }
            if let error = backgroundBackups.lastError {
                Text(verbatim: error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.statusError)
                    .accessibilityLabel("\(OpenAtLoginNote.runsWhenClosedLabel) error: \(error)")
            }
        }
        .task { backgroundBackups.refresh() }
    }
}

private struct NewCloudsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        FormSection(
            title: "New clouds",
            footer: "Clouds you already have keep their own setting. Change one from its page in Nimbus."
        ) {
            FormRow(label: "Show new clouds in Finder", help: nil) {
                Toggle("", isOn: $settings.addNewRemotesToFinder)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Show new clouds in Finder")
            }
        }
    }
}

/// Updates through Sparkle (#100). Off until the user turns them on.
private struct UpdatesSection: View {
    /// Optional so a host that has no updater (a preview) shows no section.
    @Environment(UpdaterService.self) private var updater: UpdaterService?

    var body: some View {
        if let updater {
            FormSection(
                title: "Updates",
                footer: updater.isAvailable
                    ? "Nimbus looks for a new version on GitHub only when this is on or when you check."
                    : "This build of Nimbus does not update itself."
            ) {
                FormRow(label: "Check for updates automatically", help: nil) {
                    Toggle("", isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.setAutomaticallyChecks($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!updater.isAvailable)
                    .accessibilityLabel("Check for updates automatically")
                }
                FormRow(label: "Check for a new version", help: nil) {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }
        }
    }
}

private struct AboutSettingsSection: View {
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
            HStack(spacing: DesignSystem.Spacing.l) {
                Text("Nimbus is free. More from Casa Vargas:")
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                Link("Beltr, karaoke from your own music", destination: URL(string: "https://beltr.app/?utm_source=nimbus-app&utm_medium=about&utm_campaign=nimbus")!)
                Link("OneScribe, a scanner that reads", destination: URL(string: "https://apps.apple.com/us/app/onescribe-ai-note-scanner/id6756506734")!)
                Spacer()
            }
            .font(DesignSystem.Typography.caption)
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }
}

#Preview {
    GeneralSettingsView()
        .environment(AppSettings())
        .environment(LaunchAtLoginService())
        .environment(BackgroundBackupsService(refreshOnInit: false))
        .frame(width: 680, height: 520)
}
