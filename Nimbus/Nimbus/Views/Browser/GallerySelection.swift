import Foundation

/// Which single item Gallery shows, and where the arrow keys take it.
/// Pure so the rules are testable without a view.
enum GallerySelection {
    /// The selected ID that comes first in `ids`; the first ID when nothing
    /// in the folder is selected (a stale selection counts as nothing).
    static func current(selected: Set<String>, in ids: [String]) -> String? {
        ids.first(where: selected.contains) ?? ids.first
    }

    /// The neighbour `delta` places away, stopping at either end.
    static func step(from current: String?, by delta: Int, in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return ids.first }
        return ids[min(max(index + delta, 0), ids.count - 1)]
    }
}
