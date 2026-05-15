import Foundation
import Observation

@Observable
@MainActor
final class Selection<ID: Hashable & Sendable> {
    private(set) var anchor: ID?
    private(set) var ids: Set<ID> = []

    /// Base selection snapshot: everything selected before the current
    /// shift-extend streak. Re-captured whenever the anchor is (re)set
    /// via plain select, toggle, or replace. `extend` unions this with
    /// the live anchor→target range — real Finder behavior, so a
    /// shift-click after a ⌘-click preserves disjoint selected items.
    private var baseIDs: Set<ID> = []

    func select(_ id: ID, in ordering: [ID]) {
        ids = [id]
        anchor = id
        baseIDs = [id]
    }

    func toggle(_ id: ID, in ordering: [ID]) {
        if ids.contains(id) {
            ids.remove(id)
            if anchor == id {
                anchor = ordering.first(where: { ids.contains($0) })
            }
        } else {
            ids.insert(id)
            anchor = id
        }
        baseIDs = ids
    }

    func extend(to id: ID, in ordering: [ID]) {
        // Unknown target: no-op.
        guard ordering.contains(id) else { return }

        // No anchor (or stale anchor): degrade to plain select.
        guard let anchor, ordering.contains(anchor) else {
            select(id, in: ordering)
            return
        }

        // Both endpoints known: base selection ∪ inclusive range.
        guard let a = ordering.firstIndex(of: anchor),
              let b = ordering.firstIndex(of: id) else { return }
        let lo = min(a, b)
        let hi = max(a, b)
        ids = baseIDs.union(ordering[lo...hi])
    }

    func replace(with newSet: Set<ID>, in ordering: [ID]) {
        ids = newSet
        anchor = ordering.first(where: { newSet.contains($0) })
        baseIDs = newSet
    }

    func clear() {
        ids = []
        anchor = nil
        baseIDs = []
    }
}
