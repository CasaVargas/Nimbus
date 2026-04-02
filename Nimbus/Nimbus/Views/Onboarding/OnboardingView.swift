import SwiftUI
import RcloneKit

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @State private var remotes: [String] = []
    @State private var showAddRemote = false
    @State private var loadingRemotes = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cloud")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to Nimbus")
                .font(.largeTitle.bold())

            Text("Your cloud storage, managed natively.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            GroupBox {
                HStack {
                    statusIcon
                    VStack(alignment: .leading) {
                        Text("Rclone Daemon")
                            .font(.headline)
                        Text(daemonStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            if daemon.status == .connected {
                GroupBox {
                    HStack {
                        if remotes.isEmpty {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        VStack(alignment: .leading) {
                            Text("Cloud Remotes")
                                .font(.headline)
                            if remotes.isEmpty {
                                Text("Add at least one cloud remote to get started.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(remotes.count) remote(s) configured")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if remotes.isEmpty {
                            Button("Add Remote") {
                                showAddRemote = true
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer()

            HStack {
                Button("Skip for Now") {
                    settings.onboardingComplete = true
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Get Started") {
                    settings.onboardingComplete = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(remotes.isEmpty && daemon.status == .connected)
            }
        }
        .frame(width: 500, height: 500)
        .padding(40)
        .task {
            if daemon.status == .connected {
                await loadRemotes()
            }
        }
        .onChange(of: daemon.status) {
            if daemon.status == .connected {
                Task { await loadRemotes() }
            }
        }
        .sheet(isPresented: $showAddRemote) {
            AddRemoteSheet(onComplete: {
                Task { await loadRemotes() }
            })
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch daemon.status {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .starting:
            ProgressView().controlSize(.small)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    private var daemonStatusText: String {
        switch daemon.status {
        case .idle: "Not started"
        case .starting: "Connecting..."
        case .connected: "Connected on port \(daemon.port)"
        case .error(let msg): msg
        }
    }

    private func loadRemotes() async {
        loadingRemotes = true
        defer { loadingRemotes = false }
        do {
            remotes = try await daemon.client.listRemotes()
        } catch {
            remotes = []
        }
    }
}
