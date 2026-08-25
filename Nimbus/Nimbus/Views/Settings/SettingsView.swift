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

            TransferSettingsView()
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
        .padding(.top, DesignSystem.Spacing.s)
        .frame(width: 640, height: 440)
        .background(DesignSystem.Color.semantic.surface)
    }
}
