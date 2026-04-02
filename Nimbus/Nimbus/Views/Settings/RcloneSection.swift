import SwiftUI

struct RcloneSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon

    var body: some View {
        @Bindable var settings = settings

        Form {
            TextField("Rclone Binary Path", text: $settings.rcloneBinaryPath)
            LabeledContent("Daemon Port") {
                Text("\(daemon.port)")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Daemon Status") {
                switch daemon.status {
                case .idle:
                    Text("Not running").foregroundStyle(.secondary)
                case .starting:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Starting...")
                    }
                case .connected:
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .error(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
