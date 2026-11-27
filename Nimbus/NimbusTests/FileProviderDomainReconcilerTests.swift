import Foundation
import Testing
@testable import Nimbus

@Suite("FileProviderDomainReconciler")
struct FileProviderDomainReconcilerTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func externalRemoteWithSettingOnIsAdded() {
        let plan = FileProviderDomainReconciler.plan(
            remotes: ["gdrive", "external"],
            registered: ["gdrive"],
            disabled: [],
            known: ["gdrive"],
            pendingStale: [:],
            addNewRemotesToFinder: true,
            now: now
        )
        #expect(plan.toAdd == ["external"])
        #expect(plan.toRemove.isEmpty)
        #expect(plan.newlyDisabled.isEmpty)
        #expect(plan.nextKnown == ["gdrive", "external"])
        #expect(plan.nextPendingStale.isEmpty)
    }

    @Test func externalRemoteWithSettingOffIsNewlyDisabled() {
        let plan = FileProviderDomainReconciler.plan(
            remotes: ["gdrive", "external"],
            registered: ["gdrive"],
            disabled: [],
            known: ["gdrive"],
            pendingStale: [:],
            addNewRemotesToFinder: false,
            now: now
        )
        #expect(plan.newlyDisabled == ["external"])
        #expect(plan.toAdd.isEmpty)
        #expect(plan.nextKnown == ["gdrive", "external"])
    }

    @Test func firstRunSeedsExistingRemotesEvenWithSettingOff() {
        let plan = FileProviderDomainReconciler.plan(
            remotes: ["gdrive", "s3"],
            registered: ["gdrive"],
            disabled: [],
            known: nil,
            pendingStale: [:],
            addNewRemotesToFinder: false,
            now: now
        )
        #expect(plan.newlyDisabled.isEmpty)
        #expect(plan.toAdd == ["s3"])
        #expect(plan.nextKnown == ["gdrive", "s3"])
    }

    @Test func unknownRemoteAlreadyRegisteredIsNotDisabled() {
        let plan = FileProviderDomainReconciler.plan(
            remotes: ["gdrive"],
            registered: ["gdrive"],
            disabled: [],
            known: [],
            pendingStale: [:],
            addNewRemotesToFinder: false,
            now: now
        )
        #expect(plan.newlyDisabled.isEmpty)
        #expect(plan.toAdd.isEmpty)
        #expect(plan.nextKnown == ["gdrive"])
    }

    @Test func disabledRemoteIsNotAdded() {
        let plan = FileProviderDomainReconciler.plan(
            remotes: ["gdrive", "s3"],
            registered: [],
            disabled: ["s3"],
            known: ["gdrive", "s3"],
            pendingStale: [:],
            addNewRemotesToFinder: true,
            now: now
        )
        #expect(plan.toAdd == ["gdrive"])
        #expect(plan.newlyDisabled.isEmpty)
    }

    @Test func registeredRemoteMissingOnceIsFlaggedPendingOnly() {
        let plan = FileProviderDomainReconciler.plan(
            remotes: [],
            registered: ["gdrive"],
            disabled: [],
            known: ["gdrive"],
            pendingStale: [:],
            addNewRemotesToFinder: true,
            now: now
        )
        #expect(plan.toRemove.isEmpty)
        #expect(plan.nextPendingStale == ["gdrive": now])
        #expect(plan.nextKnown == ["gdrive"])
    }

    @Test func registeredRemoteRemovedOnlyAfterConfirmationInterval() {
        let tenSecondsLater = now.addingTimeInterval(10)
        let tooSoon = FileProviderDomainReconciler.plan(
            remotes: [],
            registered: ["gdrive"],
            disabled: [],
            known: ["gdrive"],
            pendingStale: ["gdrive": now],
            addNewRemotesToFinder: true,
            now: tenSecondsLater
        )
        #expect(tooSoon.toRemove.isEmpty)
        #expect(tooSoon.nextPendingStale == ["gdrive": now])
        #expect(tooSoon.nextKnown == ["gdrive"])

        let sixtySecondsLater = now.addingTimeInterval(60)
        let confirmed = FileProviderDomainReconciler.plan(
            remotes: [],
            registered: ["gdrive"],
            disabled: [],
            known: ["gdrive"],
            pendingStale: ["gdrive": now],
            addNewRemotesToFinder: true,
            now: sixtySecondsLater
        )
        #expect(confirmed.toRemove == ["gdrive"])
        #expect(confirmed.nextKnown.isEmpty)
        #expect(confirmed.nextPendingStale.isEmpty)
    }

    @Test func exactSixtySecondBoundary() {
        let beforeBoundary = FileProviderDomainReconciler.plan(
            remotes: [],
            registered: ["gdrive"],
            disabled: [],
            known: ["gdrive"],
            pendingStale: ["gdrive": now],
            addNewRemotesToFinder: true,
            now: now.addingTimeInterval(59.9)
        )
        #expect(beforeBoundary.toRemove.isEmpty)
        #expect(beforeBoundary.nextPendingStale == ["gdrive": now])

        let atBoundary = FileProviderDomainReconciler.plan(
            remotes: [],
            registered: ["gdrive"],
            disabled: [],
            known: ["gdrive"],
            pendingStale: ["gdrive": now],
            addNewRemotesToFinder: true,
            now: now.addingTimeInterval(60.0)
        )
        #expect(atBoundary.toRemove == ["gdrive"])
        #expect(atBoundary.nextPendingStale.isEmpty)
    }

    @Test func knownRemoteWithoutDomainPrunedThenTreatedAsNewOnReturn() {
        let pruned = FileProviderDomainReconciler.plan(
            remotes: [],
            registered: [],
            disabled: [],
            known: ["s3"],
            pendingStale: ["s3": now],
            addNewRemotesToFinder: false,
            now: now.addingTimeInterval(60)
        )
        #expect(pruned.toRemove.isEmpty)
        #expect(pruned.nextKnown.isEmpty)
        #expect(pruned.nextPendingStale.isEmpty)

        let returned = FileProviderDomainReconciler.plan(
            remotes: ["s3"],
            registered: [],
            disabled: [],
            known: pruned.nextKnown,
            pendingStale: pruned.nextPendingStale,
            addNewRemotesToFinder: false,
            now: now.addingTimeInterval(120)
        )
        #expect(returned.newlyDisabled == ["s3"])
        #expect(returned.toAdd.isEmpty)
        #expect(returned.nextKnown == ["s3"])
    }

    @Test func pendingRemoteReappearingClearsPendingAndIsNotRemoved() {
        let plan = FileProviderDomainReconciler.plan(
            remotes: ["gdrive"],
            registered: ["gdrive"],
            disabled: [],
            known: ["gdrive"],
            pendingStale: ["gdrive": now],
            addNewRemotesToFinder: true,
            now: now.addingTimeInterval(120)
        )
        #expect(plan.toRemove.isEmpty)
        #expect(plan.nextPendingStale.isEmpty)
        #expect(plan.nextKnown == ["gdrive"])
    }

    @Test func plannerNeverRemovesFromDisabled() {
        let disabled: Set<String> = ["oldDisabled", "gdrive"]
        let plan = FileProviderDomainReconciler.plan(
            remotes: ["gdrive"],
            registered: [],
            disabled: disabled,
            known: ["gdrive"],
            pendingStale: [:],
            addNewRemotesToFinder: true,
            now: now
        )
        // Output only reports additions to disabled (`newlyDisabled`), never removals.
        #expect(plan.newlyDisabled.isEmpty)
        #expect(plan.toAdd.isEmpty)
        #expect(disabled.union(plan.newlyDisabled) == disabled)
    }

    @Test func legacyPendingStaleMigratesToDistantPastAndRemovesOnNextMiss() {
        let migrated = FileProviderDomainReconciler.migratedPendingStale(legacy: ["a"])
        #expect(migrated == ["a": .distantPast])

        let plan = FileProviderDomainReconciler.plan(
            remotes: [],
            registered: ["a"],
            disabled: [],
            known: ["a"],
            pendingStale: migrated,
            addNewRemotesToFinder: true,
            now: now
        )
        #expect(plan.toRemove == ["a"])
        #expect(plan.nextPendingStale.isEmpty)
        #expect(plan.nextKnown.isEmpty)
    }

    @Test func toAddPreservesListOrderAndToRemoveIsSorted() {
        let plan = FileProviderDomainReconciler.plan(
            remotes: ["z", "a"],
            registered: ["m", "b"],
            disabled: [],
            known: ["z", "a", "m", "b"],
            pendingStale: ["m": now, "b": now],
            addNewRemotesToFinder: true,
            now: now.addingTimeInterval(60)
        )
        #expect(plan.toAdd == ["z", "a"])
        #expect(plan.toRemove == ["b", "m"])
    }

    @Test func firstRunWithEmptyRemotesAndRegisteredDomainKeepsItPendingAndKnown() {
        let plan = FileProviderDomainReconciler.plan(
            remotes: [],
            registered: ["gdrive"],
            disabled: [],
            known: nil,
            pendingStale: [:],
            addNewRemotesToFinder: false,
            now: now
        )
        #expect(plan.toRemove.isEmpty)
        #expect(plan.nextPendingStale == ["gdrive": now])
        #expect(plan.nextKnown == ["gdrive"])
    }

    @Test func finalizedKeepsARemoteRecordedDuringTheReconcile() {
        let plan = FileProviderDomainReconciler.plan(
            remotes: ["gdrive"], registered: ["gdrive"], disabled: [], known: ["gdrive"],
            pendingStale: ["foo": now.addingTimeInterval(-120)], addNewRemotesToFinder: false, now: now
        )
        // "foo" was only a leftover pending entry, so the plan doesn't confirm it gone...
        #expect(plan.confirmedGone.isEmpty)
        // ...and an addDomain("foo") during the reconcile stays known.
        let saved = FileProviderDomainReconciler.finalized(
            plan: plan, liveKnown: ["gdrive", "foo"], previousPendingStale: ["foo": now.addingTimeInterval(-120)],
            failedRemovals: [], now: now
        )
        #expect(saved.known == ["gdrive", "foo"])
        #expect(saved.pendingStale.isEmpty)
    }

    @Test func finalizedDropsConfirmedGoneRemotes() {
        let since = now.addingTimeInterval(-61)
        let plan = FileProviderDomainReconciler.plan(
            remotes: [], registered: ["old"], disabled: [], known: ["old"],
            pendingStale: ["old": since], addNewRemotesToFinder: true, now: now
        )
        #expect(plan.confirmedGone == ["old"])
        let saved = FileProviderDomainReconciler.finalized(
            plan: plan, liveKnown: ["old"], previousPendingStale: ["old": since], failedRemovals: [], now: now
        )
        #expect(saved.known.isEmpty)
        #expect(saved.pendingStale.isEmpty)
    }

    @Test func finalizedKeepsAFailedRemovalKnownAndPending() {
        let since = now.addingTimeInterval(-61)
        let plan = FileProviderDomainReconciler.plan(
            remotes: [], registered: ["old"], disabled: [], known: ["old"],
            pendingStale: ["old": since], addNewRemotesToFinder: true, now: now
        )
        let saved = FileProviderDomainReconciler.finalized(
            plan: plan, liveKnown: ["old"], previousPendingStale: ["old": since], failedRemovals: ["old"], now: now
        )
        #expect(saved.known == ["old"])
        #expect(saved.pendingStale == ["old": since])
    }

    @Test func finalizedKeepsAFailedRemovalKnownOnTheFirstRun() {
        // Upgrade: no known set yet, a legacy-pending domain whose remote is gone.
        let pending = FileProviderDomainReconciler.migratedPendingStale(legacy: ["old"])
        let plan = FileProviderDomainReconciler.plan(
            remotes: [], registered: ["old"], disabled: [], known: nil,
            pendingStale: pending, addNewRemotesToFinder: false, now: now
        )
        #expect(plan.toRemove == ["old"])
        let saved = FileProviderDomainReconciler.finalized(
            plan: plan, liveKnown: [], previousPendingStale: pending, failedRemovals: ["old"], now: now
        )
        #expect(saved.known == ["old"])
        #expect(saved.pendingStale == ["old": .distantPast])
    }
}
