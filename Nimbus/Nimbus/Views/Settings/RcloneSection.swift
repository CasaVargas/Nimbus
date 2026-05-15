import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RcloneSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @State private var showingFilePicker = false

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(title: "Binary", footer: nil) {
                FormRow(label: "Path", help: nil) {
                    HStack(spacing: DesignSystem.Spacing.s) {
                        Text(verbatim: settings.rcloneBinaryPath)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { showingFilePicker = true }
                            .controlSize(.small)
                    }
                    .frame(maxWidth: 320, alignment: .trailing)
                }
                FormRow(label: "Reveal in Finder", help: nil) {
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: settings.rcloneBinaryPath)]
                        )
                    }
                    .controlSize(.small)
                }
            }
            FormSection(title: "Daemon", footer: nil) {
                FormRow(label: "Port", help: nil) {
                    Text(verbatim: "\(daemon.port)")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                }
                FormRow(label: "Status", help: nil) {
                    daemonStatusBadge
                }
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.unixExecutable]
        ) { result in
            if case .success(let url) = result {
                settings.rcloneBinaryPath = url.path
            }
        }
    }

    @ViewBuilder
    private var daemonStatusBadge: some View {
        switch daemon.status {
        case .idle:
            Text("Not running")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
        case .starting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Starting…")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.statusOK)
        case .error(let msg):
            Label {
                Text(verbatim: msg)
                    .font(DesignSystem.Typography.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(DesignSystem.Color.semantic.statusError)
        }
    }
}

#Preview {
    RcloneSection()
        .environment(AppSettings())
        .environment(RcloneDaemon())
        .frame(width: 480, height: 320)
}
