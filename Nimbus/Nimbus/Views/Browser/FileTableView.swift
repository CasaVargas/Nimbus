import AppKit

/// NSTableView subclass that routes keyDown and contextual-menu requests
/// to the Coordinator. AppKit gives us arrow-key selection and standard
/// scrolling for free; we only override the two hooks SwiftUI's Table
/// handled internally (key dispatch + context menu) so they flow through
/// Nimbus's KeyboardCoordinator / onContextAction.
final class FileTableView: NSTableView {
    /// Set by the Coordinator in makeNSView. Weak to avoid a retain cycle
    /// (Coordinator owns the scroll view which owns this table).
    weak var keyResponder: FileTableKeyResponding?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyResponder?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return nil }
        return keyResponder?.contextMenu(forRow: row)
    }
}

/// The subset of Coordinator behavior FileTableView needs. Lets the
/// subclass stay dependency-light and the Coordinator own the logic.
@MainActor
protocol FileTableKeyResponding: AnyObject {
    /// Return true if the key was handled (consumes the event).
    func handleKeyDown(_ event: NSEvent) -> Bool
    func contextMenu(forRow row: Int) -> NSMenu?
}
