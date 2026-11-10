import Foundation

/// Holds backup-notification clicks that arrive before the app has installed
/// its handler (a cold launch from Notification Center), then replays them.
struct NotificationClickBuffer {
    private var pending: [UUID?] = []

    /// Hands the click to `handler`, or keeps it while there is none.
    mutating func receive(_ id: UUID?, handler: ((UUID?) -> Void)?) {
        if let handler { handler(id) } else { pending.append(id) }
    }

    /// Replays held clicks, oldest first.
    mutating func flush(to handler: (UUID?) -> Void) {
        let held = pending
        pending.removeAll()
        held.forEach(handler)
    }
}
