import Foundation
import Observation

@Observable
@MainActor
final class Selection<ID: Hashable & Sendable> {
    private(set) var anchor: ID?
    private(set) var ids: Set<ID> = []

    func select(_ id: ID, in ordering: [ID]) {
        ids = [id]
        anchor = id
    }

    func toggle(_ id: ID) {
        if ids.contains(id) {
            ids.remove(id)
            if anchor == id { anchor = ids.first }
        } else {
            ids.insert(id)
            anchor = id
        }
    }

    func extend(to id: ID, in ordering: [ID]) {
        guard let anchor, ordering.contains(id), ordering.contains(anchor) else {
            // Without anchor or unknown id: degrade to plain select if id is known.
            if ordering.contains(id) {
                select(id, in: ordering)
            }
            return
        }
        guard let a = ordering.firstIndex(of: anchor),
              let b = ordering.firstIndex(of: id) else { return }
        let lo = min(a, b)
        let hi = max(a, b)
        ids = Set(ordering[lo...hi])
    }

    func replace(with newSet: Set<ID>, in ordering: [ID]) {
        ids = newSet
        anchor = ordering.first(where: { newSet.contains($0) })
    }

    func clear() {
        ids = []
        anchor = nil
    }
}
