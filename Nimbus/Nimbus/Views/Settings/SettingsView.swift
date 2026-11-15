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

    /// The tabs on offer: Storage only when there is a model for it.
    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0 != .storage || storageModel != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The app's own segmented control, not the system's Settings
            // toolbar: that one draws the selected tab in the accent blue
            // on a blue highlight, and takes no tint.
            GlassSegmented(
                options: tabs.map { .init(value: $0, title: $0.title, systemImage: $0.systemImage) },
                selection: $selectedTab
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings sections")
            .padding(.top, DesignSystem.Spacing.s)
            .padding(.bottom, DesignSystem.Spacing.m)

            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier("settings-shell")
        .frame(width: 680, height: 520)
        // Buttons and menus draw their label in the tint. The app's tint is
        // the theme's blue, which on this blue surface is about 1.3:1; the
        // text colour reads. Switches keep the blue (`settingsSwitch`).
        .tint(palette.textPrimary.color)
        // The same opaque surface as a sheet, so form groups match and
        // nothing here depends on what is behind the window.
        .environment(\.isOnStratosphereSheet, true)
        // Behind the title bar too, so it isn't a grey strip above the blue.
        .containerBackground(for: .window) {
            LinearGradient(colors: [palette.sheetTop.color, palette.sheetBottom.color],
                           startPoint: .top, endPoint: .bottom)
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

extension SettingsView {
    @ViewBuilder
    fileprivate var pane: some View {
        switch selectedTab {
        case .general: GeneralSettingsView()
        case .transfers: TransferSettingsView()
        case .storage:
            if let storageModel { StorageSettingsView(model: storageModel) }
        case .advanced: AdvancedSettingsView(storageModel: generalModel)
        case .about: AboutSettingsView()
        }
    }
}

extension View {
    /// A Settings switch: the system switch in the theme's action blue,
    /// which the Settings window's text-coloured tint would otherwise wash
    /// out to white on white.
    func settingsSwitch() -> some View {
        toggleStyle(.switch)
            .tint(DesignSystem.Stratosphere.Palette.dark.actionTop.color)
    }
}
