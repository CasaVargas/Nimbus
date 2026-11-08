import Foundation

extension Notification.Name {
    /// Posted after a remote is created, edited, or deleted outside the
    /// sidebar so the sidebar reloads its list.
    static let nimbusRemotesChanged = Notification.Name("app.casavargas.nimbus.remotesChanged")
    /// Home's toolbar asks the sidebar section, which owns the Add Cloud
    /// sheet, to present it.
    static let nimbusAddCloudRequested = Notification.Name("app.casavargas.nimbus.addCloudRequested")
}
