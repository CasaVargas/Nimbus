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
                ConnectionSection()
                NewCloudsSection()
                UpdatesSection()
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
                        .settingsSwitch()
                        .labelsHidden()
                        .accessibilityLabel("Open at Login")
                }
                if let error = launchAtLogin.lastError {
                    Text(verbatim: error)
                        .font(DesignSystem.Stratosphere.Typography.detail)
                        .foregroundStyle(DesignSystem.Color.semantic.statusError)
                        .accessibilityLabel("Open at Login error: \(error)")
                }
            }
            RunBackupsWhenClosedRow()
            FormRow(label: "Show in Dock", help: "When this is off, Nimbus lives in the menu bar only.") {
                Toggle("", isOn: $settings.showsDockIcon)
                    .settingsSwitch()
                    .labelsHidden()
                    .accessibilityLabel("Show in Dock")
            }
            .onChange(of: settings.showsDockIcon) { _, shows in
                DockPolicy.settingChanged(to: shows)
            }
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
                    .settingsSwitch()
                    .labelsHidden()
                    .accessibilityLabel(OpenAtLoginNote.runsWhenClosedLabel)
            }
            if backgroundBackups.needsApproval {
                HStack(spacing: DesignSystem.Spacing.s) {
                    Text("Allow Nimbus in Login Items so backups can run while it's closed.")
                        .font(DesignSystem.Stratosphere.Typography.detail)
                        .foregroundStyle(.themeText(.secondary))
                    Button("Open Login Items") { backgroundBackups.openLoginItems() }
                        .controlSize(.small)
                }
            }
            if let error = backgroundBackups.lastError {
                Text(verbatim: error)
                    .font(DesignSystem.Stratosphere.Typography.detail)
                    .foregroundStyle(DesignSystem.Color.semantic.statusError)
                    .accessibilityLabel("\(OpenAtLoginNote.runsWhenClosedLabel) error: \(error)")
            }
        }
        .task { backgroundBackups.refresh() }
    }
}

/// Idle disconnect and reconnecting from Finder (spec 2026-11-14).
private struct ConnectionSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        FormSection(
            title: "Connection",
            footer: "While Nimbus is disconnected, opening Nimbus or a drive in Finder connects again. Transfers, backups and network drives keep it connected."
        ) {
            FormRow(label: "Disconnect when idle", help: nil) {
                Picker("Disconnect when idle", selection: $settings.idleDisconnect) {
                    Text("Never").tag(IdleDisconnect.never)
                    Text("After 5 minutes").tag(IdleDisconnect.fiveMinutes)
                    Text("After 15 minutes").tag(IdleDisconnect.fifteenMinutes)
                    Text("After 30 minutes").tag(IdleDisconnect.thirtyMinutes)
                    Text("After 1 hour").tag(IdleDisconnect.oneHour)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160, alignment: .trailing)
                .accessibilityLabel("Disconnect when idle")
            }
            FormRow(label: "Open Nimbus when a drive is used in Finder",
                    help: "If Nimbus isn't running, it opens in the menu bar so your Finder drives work.") {
                Toggle("", isOn: $settings.opensAppFromFinder)
                    .settingsSwitch()
                    .labelsHidden()
                    .accessibilityLabel("Open Nimbus when a drive is used in Finder")
            }
            .onChange(of: settings.opensAppFromFinder) { _, opens in
                // The extension can't read Nimbus's preferences.
                NimbusWake.writePrefs(opensApp: opens, in: AppGroup.containerURL)
            }
        }
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
                    .settingsSwitch()
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
                    .settingsSwitch()
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

#Preview {
    GeneralSettingsView()
        .environment(AppSettings())
        .environment(LaunchAtLoginService())
        .environment(BackgroundBackupsService(refreshOnInit: false))
        .frame(width: 680, height: 520)
}
