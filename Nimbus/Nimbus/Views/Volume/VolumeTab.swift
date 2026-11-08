import Foundation

/// The four faces of a volume pane. Order is the tab order.
enum VolumeTab: String, CaseIterable, Identifiable {
    case files
    case transfers
    case finder
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "Files"
        case .transfers: "Transfers"
        case .finder: "Finder"
        case .settings: "Settings"
        }
    }
}
