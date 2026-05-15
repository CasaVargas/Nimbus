import SwiftUI

enum SettingsTab: Hashable {
    case general, appearance, transfers, rclone, storage, about
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSection()
                .tag(SettingsTab.general)
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceSection()
                .tag(SettingsTab.appearance)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            TransferSection()
                .tag(SettingsTab.transfers)
                .tabItem { Label("Transfers", systemImage: "arrow.up.arrow.down") }

            RcloneSection()
                .tag(SettingsTab.rclone)
                .tabItem { Label("Rclone", systemImage: "terminal") }

            StorageUsageView()
                .tag(SettingsTab.storage)
                .tabItem { Label("Storage", systemImage: "internaldrive") }

            AboutSection()
                .tag(SettingsTab.about)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 360)
    }
}
