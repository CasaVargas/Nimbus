import Foundation

struct FileProviderDomainPlan: Equatable {
    var toAdd: [String]
    var toRemove: [String]
    var newlyDisabled: Set<String>
    var nextKnown: Set<String>
    var nextPendingStale: [String: Date]
    /// Missing for the whole interval: dropped from known and pending.
    var confirmedGone: Set<String>
}

/// Pure planner for keeping File Provider domains aligned with rclone's
/// configured remotes across refreshes, respecting "Show new clouds in Finder"
/// and requiring a 60-second confirmation before removing a missing domain.
enum FileProviderDomainReconciler {
    static let staleConfirmationInterval: TimeInterval = 60

    static func plan(
        remotes: [String],
        registered: Set<String>,
        disabled: Set<String>,
        known: Set<String>?,
        pendingStale: [String: Date],
        addNewRemotesToFinder: Bool,
        now: Date
    ) -> FileProviderDomainPlan {
        let remoteSet = Set(remotes)

        // First run seeds with current remotes and already-registered domains
        // so existing clouds aren't treated as new.
        let baseKnown = known ?? remoteSet.union(registered)

        // A remote that already has a domain was registered on purpose, so
        // only unseen, unregistered remotes count as new.
        var newlyDisabled: Set<String> = []
        if !addNewRemotesToFinder {
            for name in remotes where !baseKnown.contains(name) && !registered.contains(name) {
                newlyDisabled.insert(name)
            }
        }

        let effectiveDisabled = disabled.union(newlyDisabled)
        let toAdd = fileProviderReconnectEligibleRemotes(from: remotes, excluding: effectiveDisabled)
            .filter { !registered.contains($0) }

        // A single listremotes can be transiently partial while rclone rewrites
        // rclone.conf, and removing a domain destroys Finder's local copy. Only
        // confirm a remote gone once it has stayed missing across the interval.
        let missing = registered.union(baseKnown).subtracting(remoteSet)
        var nextPendingStale: [String: Date] = [:]
        var confirmedGone: Set<String> = []
        var toRemove: [String] = []

        for name in missing {
            if let since = pendingStale[name] {
                if now.timeIntervalSince(since) >= staleConfirmationInterval {
                    confirmedGone.insert(name)
                    if registered.contains(name) {
                        toRemove.append(name)
                    }
                } else {
                    nextPendingStale[name] = since
                }
            } else {
                nextPendingStale[name] = now
            }
        }

        // Prune known only on confirmation so a transient partial list can't
        // turn an existing cloud into a "new" one when it reappears.
        let nextKnown = baseKnown.union(remoteSet).subtracting(confirmedGone)

        return FileProviderDomainPlan(
            toAdd: toAdd,
            toRemove: toRemove.sorted(),
            newlyDisabled: newlyDisabled,
            nextKnown: nextKnown,
            nextPendingStale: nextPendingStale,
            confirmedGone: confirmedGone
        )
    }

    /// What to persist once the plan has run. `liveKnown` is the stored set
    /// read again at the end, so a remote that `addDomain` recorded during
    /// the reconcile's awaits isn't lost. A removal that failed keeps its
    /// remote known and pending with its first-miss date, so the next
    /// reconcile retries it instead of starting the wait over.
    static func finalized(
        plan: FileProviderDomainPlan,
        liveKnown: Set<String>,
        previousPendingStale: [String: Date],
        failedRemovals: Set<String>,
        now: Date
    ) -> (known: Set<String>, pendingStale: [String: Date]) {
        let gone = plan.confirmedGone.subtracting(failedRemovals)
        let known = plan.nextKnown.union(liveKnown).subtracting(gone).union(failedRemovals)
        var pending = plan.nextPendingStale
        for id in failedRemovals {
            pending[id] = previousPendingStale[id] ?? now
        }
        return (known, pending)
    }

    /// The old format (names flagged on the previous sync) becomes
    /// "seen missing long ago", so those names keep their old meaning:
    /// removed on the next miss.
    static func migratedPendingStale(legacy: [String]) -> [String: Date] {
        Dictionary(legacy.map { ($0, Date.distantPast) }, uniquingKeysWith: { first, _ in first })
    }
}
