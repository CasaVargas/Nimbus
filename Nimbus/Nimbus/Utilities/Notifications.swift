import Foundation

extension Notification.Name {
    /// Posted after a remote is created, edited, or deleted outside the
    /// sidebar so the sidebar reloads its list.
    static let nimbusRemotesChanged = Notification.Name("app.casavargas.nimbus.remotesChanged")
    /// Posted after Keep Downloaded changes from inside the app, so file
    /// rows and the inspector re-read the pin store.
    static let nimbusPinsChanged = Notification.Name("app.casavargas.nimbus.pinsChanged")
}
