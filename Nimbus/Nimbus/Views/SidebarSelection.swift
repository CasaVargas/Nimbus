import Foundation

/// What the sidebar currently has selected. A remote selection drives the
/// detail pane to that remote's browser; the other cases map to their views.
enum SidebarSelection: Hashable {
    case remote(String)
    case copySync
}

/// Reconciles a selection against the current set of remote names. Used both
/// to auto-select on first load and to recover after a remote is deleted.
/// Non-remote selections are never altered.
func nextSelection(current: SidebarSelection?, remotes: [String]) -> SidebarSelection? {
    switch current {
    case .copySync:
        return current
    case .remote(let name):
        if remotes.contains(name) { return .remote(name) }
        return remotes.first.map(SidebarSelection.remote)
    case nil:
        return remotes.first.map(SidebarSelection.remote)
    }
}
