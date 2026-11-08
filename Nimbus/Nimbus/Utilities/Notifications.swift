import Foundation

extension Notification.Name {
    /// Posted after a remote is created, edited, or deleted outside the
    /// sidebar so the sidebar reloads its list.
    static let nimbusRemotesChanged = Notification.Name("app.casavargas.nimbus.remotesChanged")
}
