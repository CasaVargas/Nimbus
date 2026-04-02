import SwiftUI

// Value type pushed onto the NavigationStack path when the user browses a remote.
struct BrowserDestination: Hashable {
    let remoteName: String
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .remotes
    @State private var navigationPath = NavigationPath()
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon

    var body: some View {
        if !settings.onboardingComplete {
            OnboardingView()
        } else {
            NavigationSplitView {
                Sidebar(selection: $selection)
                    .frame(minWidth: 180)
            } detail: {
                NavigationStack(path: $navigationPath) {
                    detailView
                        .navigationDestination(for: BrowserDestination.self) { destination in
                            BrowserView(remoteName: destination.remoteName)
                        }
                }
            }
            .frame(minWidth: 800, minHeight: 600)
            .toolbar {
                if case .error(let message) = daemon.status {
                    ToolbarItem(placement: .status) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .environment(\.openBrowser, OpenBrowserAction { remote in
                navigationPath.append(BrowserDestination(remoteName: remote))
            })
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .remotes:
            RemotesView(onBrowse: { remote in
                navigationPath.append(BrowserDestination(remoteName: remote))
            })
        case .mounts:
            MountsView()
        case .transfers:
            TransfersView()
        case .copySync:
            CopySyncView()
        case .settings:
            SettingsView()
        case nil:
            Text("Select an item from the sidebar")
                .foregroundStyle(.secondary)
        }
    }
}

struct OpenBrowserAction {
    let action: (String) -> Void
    func callAsFunction(_ remote: String) { action(remote) }
}

extension EnvironmentValues {
    @Entry var openBrowser = OpenBrowserAction { _ in }
}
