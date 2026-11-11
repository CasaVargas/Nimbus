import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// For people who want to see under the hood: the connection engine's
/// health, which rclone it runs, network-drive defaults, and troubleshooting.
struct AdvancedSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(\.diagnosticsService) private var environmentDiagnosticsService

    @State private var storageModel: GeneralSettingsModel
    @State private var showingFilePicker = false
    @State private var diagnosticsMessage: String?
    @State private var installer = RcloneInstaller()

    init(storageModel: GeneralSettingsModel = GeneralSettingsModel()) {
        _storageModel = State(initialValue: storageModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                DaemonSettingsSection(
                    status: daemon.status,
                    version: diagnosticsService.sanitizedRcloneVersion(daemon.rcloneVersion),
                    port: daemon.port,
                    restartRequired: daemon.restartRequired(for: settings.rcloneBinaryPath),
                    actionTitle: daemonActionTitle,
                    action: runDaemonAction
                )
                RcloneSettingsSection(
                    binaryPath: settings.rcloneBinaryPath,
                    version: diagnosticsService.sanitizedRcloneVersion(daemon.rcloneVersion),
                    showFilePicker: { showingFilePicker = true },
                    revealBinary: revealBinary,
                    update: isManagedRclone ? RcloneUpdateRow.Model(
                        phase: installer.phase,
                        check: { Task { await updateRclone() } }
                    ) : nil
                )
                NetworkDriveDefaultsSection()
                DiagnosticsSettingsSection(
                    storageModel: storageModel,
                    message: diagnosticsMessage,
                    openLogs: diagnosticsService.openLogs,
                    copySystemInformation: copySystemInformation
                )
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.top)
        .accessibilityIdentifier("settings-advanced")
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.unixExecutable]
        ) { result in
            if case .success(let url) = result {
                settings.rcloneBinaryPath = url.path
            }
        }
    }

    @MainActor
    private var diagnosticsService: DiagnosticsService {
        environmentDiagnosticsService ?? DiagnosticsService()
    }

    private var daemonActionTitle: String? {
        switch daemon.status {
        case .starting:
            nil
        case .idle:
            "Start"
        case .connected:
            daemon.restartRequired(for: settings.rcloneBinaryPath) ? "Restart Now" : "Restart"
        case .error:
            "Retry"
        }
    }

    /// Only the copy Nimbus downloaded gets an update button; Homebrew
    /// updates its own.
    private var isManagedRclone: Bool {
        settings.rcloneBinaryPath == RcloneInstaller.managedBinaryPath
    }

    private func updateRclone() async {
        let installed = daemon.rcloneVersion.flatMap(RcloneRelease.parseVersion)
        guard await installer.update(installedVersion: installed) != nil else { return }
        await daemon.restart(
            binaryPath: settings.rcloneBinaryPath,
            bandwidthLimit: settings.bandwidthLimit,
            concurrentTransfers: settings.concurrentTransfers
        )
    }

    private func revealBinary() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: settings.rcloneBinaryPath)])
    }

    @MainActor
    private func runDaemonAction() {
        diagnosticsMessage = nil
        Task { @MainActor in
            switch daemon.status {
            case .starting:
                break
            case .idle:
                await daemon.start(
                    binaryPath: settings.rcloneBinaryPath,
                    bandwidthLimit: settings.bandwidthLimit,
                    concurrentTransfers: settings.concurrentTransfers
                )
            case .connected, .error:
                await daemon.restart(
                    binaryPath: settings.rcloneBinaryPath,
                    bandwidthLimit: settings.bandwidthLimit,
                    concurrentTransfers: settings.concurrentTransfers
                )
            }
        }
    }

    private func copySystemInformation() {
        let text = diagnosticsService.systemInformation(daemon: daemon)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        diagnosticsMessage = "Copied system information."
    }
}

private struct RcloneSettingsSection: View {
    let binaryPath: String
    let version: String
    let showFilePicker: () -> Void
    let revealBinary: () -> Void
    var update: RcloneUpdateRow.Model?

    var body: some View {
        FormSection(
            title: "rclone",
            footer: update == nil ? nil : "Nimbus downloaded this rclone from rclone.org. It only checks for a newer one when you ask."
        ) {
            FormRow(label: "Location", help: nil) {
                HStack(spacing: DesignSystem.Spacing.s) {
                    Text(verbatim: binaryPath)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button("Choose…", action: showFilePicker)
                        .controlSize(.small)
                    Button("Reveal", action: revealBinary)
                        .controlSize(.small)
                }
                .frame(maxWidth: 380, alignment: .trailing)
            }
            FormRow(label: "Version", help: nil) {
                Text(verbatim: version)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .accessibilityLabel("rclone version \(version)")
            }
            if let update {
                RcloneUpdateRow(model: update)
            }
        }
    }
}

/// "Check for Update" for the rclone Nimbus downloaded, with the outcome.
struct RcloneUpdateRow: View {
    struct Model {
        let phase: RcloneInstaller.Phase
        let check: () -> Void
    }

    let model: Model

    var body: some View {
        FormRow(label: "Updates", help: nil) {
            HStack(spacing: DesignSystem.Spacing.s) {
                if model.phase.isBusy {
                    ProgressView().controlSize(.small)
                }
                if let status {
                    Text(verbatim: status)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                Button("Check for Update", action: model.check)
                    .controlSize(.small)
                    .disabled(model.phase.isBusy)
            }
            .frame(maxWidth: 380, alignment: .trailing)
        }
    }

    private var status: String? {
        switch model.phase {
        case .idle: nil
        case .checking: "Checking rclone.org…"
        case .downloading(let version): "Downloading \(version)…"
        case .verifying: "Verifying…"
        case .installing: "Installing…"
        case .installed(let version): "Updated to \(version)."
        case .upToDate(let version): "\(version) is the latest."
        case .failed(let failure): failure.message
        }
    }
}

/// One status line for the engine that talks to every cloud, with the one
/// action that fits its state. Port and version are detail, not headline.
private struct DaemonSettingsSection: View {
    let status: RcloneDaemon.Status
    let version: String
    let port: Int
    let restartRequired: Bool
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        FormSection(
            title: "Connection engine",
            footer: "Nimbus uses rclone to talk to your clouds. It starts with Nimbus and restarts on its own after most problems."
        ) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.m) {
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: headline)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                        .lineLimit(2)
                    Text(verbatim: detail)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(restartRequired ? DesignSystem.Color.semantic.statusWarning
                                                         : DesignSystem.Color.semantic.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: DesignSystem.Spacing.m)
                if let actionTitle {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                        .accessibilityLabel(actionTitle)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
            .accessibilityElement(children: .contain)
        }
    }

    private var headline: String {
        switch status {
        case .idle: "Stopped"
        case .starting: "Starting…"
        case .connected: "Running"
        case .error(let message): message
        }
    }

    private var detail: String {
        if restartRequired { return "Restart to use the rclone you chose." }
        switch status {
        case .connected: return "rclone \(version) on port \(port)"
        case .starting: return "rclone \(version)"
        case .idle: return "Start it to reach your clouds."
        case .error: return "Try again, or choose a different rclone below."
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch status {
        case .starting:
            ProgressView().controlSize(.small)
        default:
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
    }

    private var dotColor: Color {
        switch status {
        case .connected: DesignSystem.Color.semantic.statusOK
        case .error: DesignSystem.Color.semantic.statusError
        case .idle, .starting: DesignSystem.Color.semantic.statusMuted
        }
    }
}

/// Defaults for NFS network drives, moved here from General: most people use
/// Show in Finder, and these only apply to drives added later.
private struct NetworkDriveDefaultsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        FormSection(
            title: "Network drives",
            footer: "Applies to network drives you add later. Most people use Show in Finder instead."
        ) {
            FormRow(label: "Access for new network drives", help: nil) {
                Picker("Access for new network drives", selection: $settings.newMountAccess) {
                    Text("Read & write").tag(MountAccessDefault.readWrite)
                    Text("Read only").tag(MountAccessDefault.readOnly)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 140, alignment: .trailing)
                .accessibilityLabel("Access for new network drives")
            }
            FormRow(label: "Connect new network drives at login", help: nil) {
                Toggle("", isOn: $settings.newMountAutoMount)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Connect new network drives at login")
            }
        }
    }
}

private struct DiagnosticsSettingsSection: View {
    let storageModel: GeneralSettingsModel
    let message: String?
    let openLogs: () -> Void
    let copySystemInformation: () -> Void

    var body: some View {
        FormSection(
            title: "Troubleshooting",
            footer: "System information leaves out cloud names, passwords, and file paths."
        ) {
            FinderChangeRecordsRow(model: storageModel)
            FormRow(label: "Logs", help: nil) {
                Button("Open in Console", action: openLogs)
                    .controlSize(.small)
                    .accessibilityLabel("Open logs in Console")
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                FormRow(label: "System information", help: nil) {
                    Button("Copy", action: copySystemInformation)
                        .controlSize(.small)
                        .accessibilityLabel("Copy system information")
                }
                if let message {
                    Text(verbatim: message)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel(message)
                }
            }
        }
    }
}

#Preview {
    AdvancedSettingsView(storageModel: GeneralSettingsModel(cacheUsage: .available(4_200_000)))
        .environment(AppSettings())
        .environment(RcloneDaemon())
        .environment(\.diagnosticsService, DiagnosticsService())
        .frame(width: 680, height: 450)
}
