import Foundation

/// Storage added up across clouds: what Home's summary and the sidebar's
/// footer both show.
struct StorageTotals: Equatable {
    /// Sum of every known `used`.
    let usedBytes: Int64
    /// Sum of `free` over clouds that report a limit; nil when none do, so
    /// nothing invents free space for pay-as-you-go storage.
    let freeBytes: Int64?
    /// Width of an aggregate bar: limits where known, plus usage for clouds
    /// without one, so the bar never overflows.
    let capacityBytes: Int64

    /// A limit this large is an organisation's shared pool, not one
    /// person's plan: a Google Workspace account reports the whole pool
    /// (hundreds of TB) as its total. Counting that as free space makes
    /// every other cloud round to nothing, so a pooled account is added up
    /// like pay-as-you-go storage: its usage counts, its limit doesn't.
    /// 100 TB sits well above the largest personal plans (30 TB).
    static let pooledLimitBytes: Int64 = 100_000_000_000_000

    init(quotas: [StorageQuota]) {
        var used: Int64 = 0
        var free: Int64?
        var capacity: Int64 = 0
        for quota in quotas {
            if let u = quota.used { used += u }
            if let total = quota.total, total < Self.pooledLimitBytes {
                capacity += total
                if let f = quota.free { free = (free ?? 0) + f }
            } else if let u = quota.used {
                capacity += u
            }
        }
        usedBytes = used
        freeBytes = free
        capacityBytes = capacity
    }

    /// Used ÷ capacity, or nil when nothing is known yet.
    var usedFraction: Double? {
        capacityBytes > 0 ? Double(usedBytes) / Double(capacityBytes) : nil
    }

    /// One cloud's usage as a share of the whole bar, 0...1.
    func share(of quota: StorageQuota) -> Double {
        guard capacityBytes > 0, let used = quota.used else { return 0 }
        return min(1, max(0, Double(used) / Double(capacityBytes)))
    }
}
