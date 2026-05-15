import Testing
import Foundation
@testable import Nimbus

@Suite("TimedCache")
struct TimedCacheTests {
    @Test func hitWithinTTLReturnsCachedValue() {
        let cache = TimedCache<String, Int>(ttl: .seconds(60))
        cache.store(42, for: "a")
        #expect(cache.value(for: "a") == 42)
    }

    @Test func missAfterTTLReturnsNil() async throws {
        let cache = TimedCache<String, Int>(ttl: .milliseconds(50))
        cache.store(42, for: "a")
        try await Task.sleep(for: .milliseconds(100))
        #expect(cache.value(for: "a") == nil)
    }

    @Test func invalidateRemovesEntry() {
        let cache = TimedCache<String, Int>(ttl: .seconds(60))
        cache.store(42, for: "a")
        cache.invalidate("a")
        #expect(cache.value(for: "a") == nil)
    }
}
