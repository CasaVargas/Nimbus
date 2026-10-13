import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(\.diagnosticsService) private var environmentDiagnosticsService

    @State private var showingFilePicker = false
    @State private var diagnosticsMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                RcloneSettingsSection(
                    binaryPath: settings.rcloneBinaryPath,
                    version: diagnosticsService.sanitizedRcloneVersion(daemon.rcloneVersion),
                    showFilePicker: { showingFilePicker = true },
                    revealBinary: revealBinary
                )
                DaemonSettingsSection(
                    status: daemon.status,
                    port: daemon.port,
                    restartRequired: daemon.restartRequired(for: settings.rcloneBinaryPath),
                    actionTitle: daemonActionTitle,
                    action: runDaemonAction
                )
                DiagnosticsSettingsSection(
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

    var body: some View {
        FormSection(title: "Rclone", footer: nil) {
            FormRow(label: "Binary Path", help: nil) {
                HStack(spacing: DesignSystem.Spacing.s) {
                    Text(verbatim: binaryPath)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose...", action: showFilePicker)
                        .controlSize(.small)
                    Button("Reveal", action: revealBinary)
                        .controlSize(.small)
                }
                .frame(maxWidth: 360, alignment: .trailing)
            }
            FormRow(label: "Detected Version", help: nil) {
                Text(verbatim: version)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .accessibilityLabel("Detected Version \(version)")
            }
        }
    }
}

private struct DaemonSettingsSection: View {
    let status: RcloneDaemon.Status
    let port: Int
    let restartRequired: Bool
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        FormSection(title: "Daemon", footer: nil) {
            FormRow(label: "Status", help: nil) {
                daemonStatusView
            }
            FormRow(label: "Port", help: nil) {
                Text(verbatim: "\(port)")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
            if restartRequired {
                statusMessage(
                    text: "Restart Required",
                    systemImage: "arrow.clockwise.circle.fill",
                    color: DesignSystem.Color.semantic.statusWarning
                )
            }
            if let actionTitle {
                FormRow(label: "Action", help: nil) {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                        .accessibilityLabel(actionTitle)
                }
            }
        }
    }

    @ViewBuilder
    private var daemonStatusView: some View {
        switch status {
        case .idle:
            Label("Not Running", systemImage: "pause.circle")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
        case .starting:
            HStack(spacing: DesignSystem.Spacing.s) {
                ProgressView()
                    .controlSize(.small)
                Text("Starting...")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.statusOK)
        case .error(let message):
            statusMessage(
                text: message,
                systemImage: "exclamationmark.triangle.fill",
                color: DesignSystem.Color.semantic.statusError
            )
        }
    }

    private func statusMessage(text: String, systemImage: String, color: Color) -> some View {
        Label {
            Text(verbatim: text)
                .lineLimit(2)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(DesignSystem.Typography.caption)
        .foregroundStyle(color)
        .frame(maxWidth: 320, alignment: .trailing)
    }
}

private struct DiagnosticsSettingsSection: View {
    let message: String?
    let openLogs: () -> Void
    let copySystemInformation: () -> Void

    var body: some View {
        FormSection(
            title: "Diagnostics",
            footer: "Copied system information excludes remote names, credentials, and file paths."
        ) {
            FormRow(label: "Logs", help: nil) {
                Button("Open Logs in Console", action: openLogs)
                    .controlSize(.small)
                    .accessibilityLabel("Open Logs in Console")
            }
            FormRow(label: "System Information", help: nil) {
                Button("Copy System Information", action: copySystemInformation)
                    .controlSize(.small)
                    .accessibilityLabel("Copy System Information")
            }
            if let message {
                Text(verbatim: message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .accessibilityLabel(message)
            }
        }
    }
}

#Preview {
    AdvancedSettingsView()
        .environment(AppSettings())
        .environment(RcloneDaemon())
        .environment(\.diagnosticsService, DiagnosticsService())
        .frame(width: 680, height: 450)
}
