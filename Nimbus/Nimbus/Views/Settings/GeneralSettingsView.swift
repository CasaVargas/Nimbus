import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @State private var model: GeneralSettingsModel

    init(model: GeneralSettingsModel = GeneralSettingsModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                ApplicationSettingsSection()
                FinderDefaultsSection()
                StorageUsageView(model: model)
                AboutSettingsSection()
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("settings-general")
    }
}

private struct ApplicationSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    var body: some View {
        @Bindable var settings = settings

        FormSection(title: "Application", footer: nil) {
            FormRow(label: "Launch at Login", help: nil) {
                Toggle("", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Launch at Login")
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
            if let error = launchAtLogin.lastError {
                Text(verbatim: error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.statusError)
                    .accessibilityLabel("Launch at login error: \(error)")
            }
        }
        .onAppear { launchAtLogin.refresh() }
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

private struct FinderDefaultsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        FormSection(
            title: "Finder",
            footer: "These defaults apply only to remote and mount configurations created later. Existing Finder domains and mounts are unchanged."
        ) {
            FormRow(label: "Add New Remotes to Finder", help: nil) {
                Toggle("", isOn: $settings.addNewRemotesToFinder)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Add New Remotes to Finder")
            }
            FormRow(label: "New Mount Access", help: nil) {
                Picker("New Mount Access", selection: $settings.newMountAccess) {
                    Text("Read & Write").tag(MountAccessDefault.readWrite)
                    Text("Read Only").tag(MountAccessDefault.readOnly)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 140, alignment: .trailing)
                .accessibilityLabel("New Mount Access")
            }
            FormRow(label: "Mount New Volumes at Login", help: nil) {
                Toggle("", isOn: $settings.newMountAutoMount)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Mount New Volumes at Login")
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

    var body: some View {
        FormSection(title: "About", footer: nil) {
            HStack(spacing: DesignSystem.Spacing.m) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Nimbus")
                        .font(DesignSystem.Typography.headline)
                    Text("Version \(version) (\(build))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    Text("© 2026 CasaVargas LLC")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                }
                Spacer()
                Link("rclone", destination: URL(string: "https://rclone.org/")!)
                    .accessibilityLabel("Visit rclone website")
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }
}

#Preview {
    GeneralSettingsView()
        .environment(AppSettings())
        .environment(LaunchAtLoginService())
        .frame(width: 680, height: 450)
}
