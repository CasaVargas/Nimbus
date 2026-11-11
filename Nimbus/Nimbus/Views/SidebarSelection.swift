import Foundation

/// What the sidebar currently has selected. Home is the landing screen; a
/// remote selection drives the detail pane to that cloud's volume page; the
/// other cases map to their views.
enum SidebarSelection: Hashable {
    case home
    case remote(String)
    case copySync
    case backups
    case compare
}

/// Reconciles a selection against the current set of remote names. Used both
/// to pick the first screen and to recover after a remote is deleted: both
/// land on Home, which is always valid. Non-remote selections are never altered.
func nextSelection(current: SidebarSelection?, remotes: [String]) -> SidebarSelection? {
    switch current {
    case .home, .copySync, .backups, .compare:
        return current
    case .remote(let name):
        return remotes.contains(name) ? .remote(name) : .home
    case nil:
        return .home
    }
}
