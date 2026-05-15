import Foundation

/// Reference-semantics cache with per-entry TTL. Used by `FileProviderBridge`
/// to avoid hammering `NSFileProviderManager` for materialized/evicted
/// queries on every row scroll. Not thread-safe — callers are expected to
/// be `@MainActor`-isolated.
final class TimedCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let storedAt: Date
    }

    private let ttl: Duration
    private var storage: [Key: Entry] = [:]

    init(ttl: Duration) {
        self.ttl = ttl
    }

    func value(for key: Key) -> Value? {
        guard let entry = storage[key] else { return nil }
        let age = Date().timeIntervalSince(entry.storedAt)
        let ttlSeconds = Double(ttl.components.seconds) +
                         Double(ttl.components.attoseconds) / 1e18
        if age > ttlSeconds {
            storage.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func store(_ value: Value, for key: Key) {
        storage[key] = Entry(value: value, storedAt: Date())
    }

    func invalidate(_ key: Key) {
        storage.removeValue(forKey: key)
    }

    func invalidateAll() {
        storage.removeAll()
    }
}
