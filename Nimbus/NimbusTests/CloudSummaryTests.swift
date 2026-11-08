import Testing
import Foundation
import RcloneKit
@testable import Nimbus

@Suite("CloudSummaryBuilder")
@MainActor
struct CloudSummaryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func remote(_ name: String, _ type: String = "drive") -> Remote {
        Remote(name: name, type: type, config: [:])
    }

    func transfer(src: String, dst: String, eta: TimeInterval? = nil, progress: Double = 0.5,
                  status: TransferStatus = .active, op: TransferOperation = .copy,
                  completedAt: Date? = nil) -> Transfer {
        Transfer(jobID: 1, operation: op, srcFs: src, dstFs: dst, startedAt: now,
                 completedAt: completedAt, status: status, origin: .manual,
                 nimbusUUID: UUID(), progress: progress, eta: eta)
    }

    func build(
        _ remotes: [Remote],
        statuses: [String: RemoteStatus] = [:],
        quotas: [String: StorageQuota] = [:],
        transfers: [Transfer] = [],
        inFinder: Set<String>? = nil,
        lastConnected: [String: Date] = [:],
        dismissed: Set<String> = [],
        daemon: RcloneDaemon.Status = .connected
    ) -> CloudSummary {
        CloudSummaryBuilder.build(
            remotes: remotes, statuses: statuses, quotas: quotas,
            activeTransfers: transfers,
            isInFinder: { inFinder?.contains($0) ?? true },
            providerName: { $0 == "drive" ? "Google Drive" : $0 },
            lastConnected: lastConnected, dismissedSuggestions: dismissed,
            daemon: daemon, now: now
        )
    }

    // MARK: Status sentences

    @Test func connectedReadsReady() {
        let s = build([remote("Personal")], statuses: ["Personal": .connected])
        #expect(s.rows[0].health == .ready)
        #expect(s.rows[0].sentence == "Ready")
        #expect(s.rows[0].providerName == "Google Drive")
        #expect(s.overall == .allReady)
    }

    @Test func eachStatusMapsToPlainSentence() {
        let cases: [(RemoteStatus, CloudSummary.Health, String)] = [
            (.unknown, .checking, "Checking…"),
            (.authNeeded, .needsSignIn, "Needs sign-in"),
            (.unreachable(reason: "no route to host"), .unreachable, "Can't reach this server right now"),
            (.error(reason: "bad config"), .failing, "Can't connect"),
        ]
        for (status, health, sentence) in cases {
            let row = build([remote("A")], statuses: ["A": status]).rows[0]
            #expect(row.health == health)
            #expect(row.sentence == sentence)
        }
    }

    @Test func uploadsWinOverStatusAndCarryETA() {
        let s = build([remote("Dropbox", "dropbox")], statuses: ["Dropbox": .connected],
                      transfers: [transfer(src: "Personal:a", dst: "Dropbox:x", eta: 120),
                                  transfer(src: "Personal:b", dst: "Dropbox:y", eta: 30),
                                  transfer(src: "Personal:c", dst: "Dropbox:z")])
        #expect(s.rows[0].health == .busy)
        #expect(s.rows[0].sentence == "Uploading 3 items, 2 min left")
    }

    @Test func downloadSentenceWhenCloudIsSource() {
        let s = build([remote("Personal")], statuses: ["Personal": .connected],
                      transfers: [transfer(src: "Personal:a", dst: "Work:b")])
        #expect(s.rows[0].sentence == "Downloading 1 item")
    }

    @Test func remoteNamePrefixDoesNotMatchLongerName() {
        let s = build([remote("Drive"), remote("Drive2")],
                      statuses: ["Drive": .connected, "Drive2": .connected],
                      transfers: [transfer(src: "local:/x", dst: "Drive2:y")])
        #expect(s.rows[0].health == .ready)
        #expect(s.rows[1].health == .busy)
    }

    @Test func etaWording() {
        #expect(CloudSummaryBuilder.etaText(20) == "less than a minute")
        #expect(CloudSummaryBuilder.etaText(70) == "1 min")
        #expect(CloudSummaryBuilder.etaText(600) == "10 min")
        #expect(CloudSummaryBuilder.etaText(5400) == "about 2 hours")
    }

    // MARK: Overall + attention

    @Test func daemonStatesOverrideEverything() {
        #expect(build([remote("A")], daemon: .starting).overall == .starting)
        #expect(build([remote("A")], daemon: .error("boom")).overall == .engineDown("boom"))
        #expect(build([]).overall == .noClouds)
    }

    @Test func attentionPriorityIsSignInThenFailingThenUnreachable() {
        let remotes = [remote("N"), remote("F"), remote("S")]
        let s = build(remotes, statuses: ["N": .unreachable(reason: "x"), "F": .error(reason: "y"), "S": .authNeeded])
        #expect(s.attention?.id == "S")
        #expect(s.overall == .needsAttention(s.rows[2]))

        let s2 = build(remotes, statuses: ["N": .unreachable(reason: "x"), "F": .error(reason: "y"), "S": .connected])
        #expect(s2.attention?.id == "F")
    }

    @Test func recentlySeenUnreachableCloudGetsNoBanner() {
        let recent = now.addingTimeInterval(-3600)
        let old = now.addingTimeInterval(-3 * 24 * 3600)
        let s = build([remote("NAS", "sftp")], statuses: ["NAS": .unreachable(reason: "x")],
                      lastConnected: ["NAS": recent])
        #expect(s.attention == nil)
        #expect(s.rows[0].lastConnected == recent)
        let s2 = build([remote("NAS", "sftp")], statuses: ["NAS": .unreachable(reason: "x")],
                       lastConnected: ["NAS": old])
        #expect(s2.attention?.id == "NAS")
    }

    @Test func busyOverallNamesSingleDestination() {
        let s = build([remote("A"), remote("B")], statuses: ["A": .connected, "B": .connected],
                      transfers: [transfer(src: "A:x", dst: "B:x", progress: 0.2),
                                  transfer(src: "A:y", dst: "B:y", progress: 0.6)])
        guard case .busy(let busy) = s.overall else { Issue.record("expected busy"); return }
        #expect(busy.sentence == "Copying 2 items to B")
        #expect(abs(busy.progress - 0.4) < 0.0001)
    }

    // MARK: Bar math

    @Test func barMathMixesLimitedAndPayAsYouGo() {
        let s = build(
            [remote("P"), remote("B2", "b2"), remote("NAS", "sftp")],
            statuses: ["P": .connected, "B2": .connected, "NAS": .unreachable(reason: "x")],
            quotas: ["P": StorageQuota(used: 1_200, total: 2_000),
                     "B2": StorageQuota(used: 700, total: nil)]
        )
        #expect(s.usedBytes == 1_900)
        #expect(s.freeBytes == 800)
        #expect(s.capacityBytes == 2_700)
    }

    @Test func freeIsNilWhenNoCloudReportsALimit() {
        let s = build([remote("B2", "b2")], statuses: ["B2": .connected],
                      quotas: ["B2": StorageQuota(used: 700, total: nil)])
        #expect(s.freeBytes == nil)
        #expect(s.capacityBytes == 700)
    }

    @Test func tintsFollowSidebarOrderAndClampToLastSlot() {
        let remotes = (0..<10).map { remote("R\($0)") }
        let tints = build(remotes).rows.map(\.tint)
        #expect(tints == [0, 1, 2, 3, 4, 5, 6, 7, 7, 7])
    }

    // MARK: Suggestions

    @Test func suggestsNearlyFullAndNotInFinderRespectingDismissals() {
        let remotes = [remote("Full"), remote("Hidden")]
        let s = build(remotes, statuses: ["Full": .connected, "Hidden": .connected],
                      quotas: ["Full": StorageQuota(used: 95, total: 100)],
                      inFinder: ["Full"])
        #expect(s.suggestions.map(\.id) == ["full:Full", "finder:Hidden"])
        let s2 = build(remotes, statuses: ["Full": .connected, "Hidden": .connected],
                       quotas: ["Full": StorageQuota(used: 95, total: 100)],
                       inFinder: ["Full"], dismissed: ["finder:Hidden"])
        #expect(s2.suggestions.map(\.id) == ["full:Full"])
    }

    // MARK: Activity

    @Test func activityLinesWordFinishedTransfersNewestFirst() {
        let lines = ActivityLine.lines(from: [
            transfer(src: "Personal:Photos/Yosemite 2026", dst: "Archive:", status: .completed,
                     completedAt: now.addingTimeInterval(-100)),
            transfer(src: "Personal:", dst: "Dropbox:Backup", status: .failed("x"), op: .sync,
                     completedAt: now),
            transfer(src: "A:x", dst: "B:", status: .cancelled, completedAt: now),
        ])
        #expect(lines.map(\.text) == ["Couldn't sync Personal to Dropbox",
                                      "Copied Yosemite 2026 to Archive"])
        #expect(lines[0].isFailure)
        #expect(lines[1].cloud == "Archive")
    }
    // MARK: Aliases

    @Test func aliasResolvesToTargetBackendAndStopsOnCycles() {
        let gdrive = Remote(name: "gdrive", type: "drive", config: [:])
        let personal = Remote(name: "Personal Drive", type: "alias", config: ["remote": "gdrive:Personal"])
        let local = Remote(name: "Desk", type: "alias", config: ["remote": "/Users/me/Desktop"])
        let loopA = Remote(name: "A", type: "alias", config: ["remote": "B:"])
        let loopB = Remote(name: "B", type: "alias", config: ["remote": "A:"])
        let all = [gdrive, personal, local, loopA, loopB]
        #expect(CloudNaming.resolvedType(of: personal, in: all) == "drive")
        #expect(CloudNaming.resolvedType(of: local, in: all) == "alias")
        #expect(CloudNaming.resolvedType(of: loopA, in: all) == "alias")

        let s = CloudSummaryBuilder.build(
            remotes: [gdrive, personal], statuses: [:], quotas: [:], activeTransfers: [],
            isInFinder: { _ in true }, providerName: { $0 == "drive" ? "Google Drive" : $0 },
            lastConnected: [:], dismissedSuggestions: [], daemon: .connected, now: now,
            resolveType: { CloudNaming.resolvedType(of: $0, in: [gdrive, personal]) }
        )
        #expect(s.rows[1].providerType == "drive")
        #expect(s.rows[1].providerName == "Google Drive")
    }
}
