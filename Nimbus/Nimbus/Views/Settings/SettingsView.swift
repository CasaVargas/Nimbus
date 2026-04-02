import SwiftUI

enum SettingsTab: Hashable {
    case appearance, transfers, rclone, about
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .appearance

    var body: some View {
        TabView(selection: $selectedTab) {
            AppearanceSection()
                .tag(SettingsTab.appearance)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            TransferSection()
                .tag(SettingsTab.transfers)
                .tabItem { Label("Transfers", systemImage: "arrow.up.arrow.down") }

            RcloneSection()
                .tag(SettingsTab.rclone)
                .tabItem { Label("Rclone", systemImage: "terminal") }

            AboutSection()
                .tag(SettingsTab.about)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 250)
        .padding()
    }
}
