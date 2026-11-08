import SwiftUI

enum SettingsTab: String, CaseIterable, Hashable {
    case general
    case transfers
    case advanced

    var title: String {
        switch self {
        case .general: "General"
        case .transfers: "Transfers"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .transfers: "arrow.up.arrow.down"
        case .advanced: "slider.horizontal.3"
        }
    }
}

struct SettingsView: View {
    private let generalModel: GeneralSettingsModel
    @State private var selectedTab: SettingsTab = .general

    init(generalModel: GeneralSettingsModel = GeneralSettingsModel()) {
        self.generalModel = generalModel
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tag(SettingsTab.general)
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage) }

            TransferSettingsView()
                .tag(SettingsTab.transfers)
                .tabItem { Label(SettingsTab.transfers.title, systemImage: SettingsTab.transfers.systemImage) }

            AdvancedSettingsView(storageModel: generalModel)
                .tag(SettingsTab.advanced)
                .tabItem { Label(SettingsTab.advanced.title, systemImage: SettingsTab.advanced.systemImage) }
        }
        .accessibilityIdentifier("settings-shell")
        .frame(width: 680, height: 520)
        .background(DesignSystem.Color.semantic.surface)
    }
}
