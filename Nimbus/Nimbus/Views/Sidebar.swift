import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case remotes = "Remotes"
    case mounts = "Mounts"
    case transfers = "Transfers"
    case copySync = "Copy / Sync"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .remotes: "cloud"
        case .mounts: "externaldrive"
        case .transfers: "arrow.up.arrow.down"
        case .copySync: "doc.on.doc"
        case .settings: "gear"
        }
    }
}

struct Sidebar: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("Nimbus")
    }
}
