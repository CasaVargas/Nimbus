import SwiftUI

enum SettingsTab: String, CaseIterable, Hashable {
    case general
    case transfers
    case storage
    case advanced
    case about

    var title: String {
        switch self {
        case .general: "General"
        case .transfers: "Transfers"
        case .storage: "Storage"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .transfers: "arrow.up.arrow.down"
        case .storage: "internaldrive"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    private let generalModel: GeneralSettingsModel
    private let storageModel: DownloadedStorageModel?
    @State private var selectedTab: SettingsTab = .general
    @Environment(\.stratosphere) private var palette

    init(generalModel: GeneralSettingsModel = GeneralSettingsModel(),
         storageModel: DownloadedStorageModel? = nil) {
        self.generalModel = generalModel
        self.storageModel = storageModel
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tag(SettingsTab.general)
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage) }

            TransferSettingsView()
                .tag(SettingsTab.transfers)
                .tabItem { Label(SettingsTab.transfers.title, systemImage: SettingsTab.transfers.systemImage) }

            if let storageModel {
                StorageSettingsView(model: storageModel)
                    .tag(SettingsTab.storage)
                    .tabItem { Label(SettingsTab.storage.title, systemImage: SettingsTab.storage.systemImage) }
            }

            AdvancedSettingsView(storageModel: generalModel)
                .tag(SettingsTab.advanced)
                .tabItem { Label(SettingsTab.advanced.title, systemImage: SettingsTab.advanced.systemImage) }

            AboutSettingsView()
                .tag(SettingsTab.about)
                .tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.systemImage) }
        }
        .accessibilityIdentifier("settings-shell")
        .frame(width: 680, height: 520)
        // The same opaque surface as a sheet, so form groups match and
        // nothing here depends on what is behind the window.
        .environment(\.isOnStratosphereSheet, true)
        .background(LinearGradient(colors: [palette.sheetTop.color, palette.sheetBottom.color],
                                   startPoint: .top, endPoint: .bottom))
    }
}
