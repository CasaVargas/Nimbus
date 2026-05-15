import AppKit

/// Pure classification of a pointer/keyboard selection gesture into one
/// of the three Selection operations. The actual range/anchor math lives
/// in `Selection<ID>` (already tested) — this type only decides WHICH
/// Selection method a given NSEvent modifier set maps to, and forwards.
/// Keeping this separate from `Selection` keeps the AppKit-event
/// interpretation testable without a live NSTableView.
enum SelectionIntent: Equatable, Sendable {
    case select   // plain click / plain arrow → Selection.select
    case toggle   // ⌘-click → Selection.toggle
    case extend   // ⇧-click / ⇧-arrow → Selection.extend

    /// Finder precedence: Command beats Shift. A bare click is `.select`.
    static func forClick(modifiers: NSEvent.ModifierFlags) -> SelectionIntent {
        if modifiers.contains(.command) { return .toggle }
        if modifiers.contains(.shift) { return .extend }
        return .select
    }

    @MainActor
    func apply(to selection: Selection<String>, id: String, ordering: [String]) {
        switch self {
        case .select: selection.select(id, in: ordering)
        case .toggle: selection.toggle(id, in: ordering)
        case .extend: selection.extend(to: id, in: ordering)
        }
    }
}
