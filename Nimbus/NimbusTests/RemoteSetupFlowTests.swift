import Testing
import Foundation
import RcloneKit
@testable import Nimbus

/// Scripts a sequence of `config/create` replies so the flow can be walked
/// without a live rclone. Mirrors the fixture style in ProviderPickerTests:
/// RcloneKit models are decode-only.
///
/// Scripts are keyed on `askAll` — `scriptFalse` for `askAll: false` calls,
/// `scriptTrue` for `askAll: true` — because that asymmetry (an OAuth
/// backend answering straight from `all:false`; a credential backend asking
/// nothing until `all:true`) is the single most important behavior
/// RemoteSetupFlow implements, and a client that ignores `askAll` can't
/// model it (S4 in fix round 1's supplement).
@MainActor
private final class ScriptedConfigClient: RemoteConfigDriving {
    var scriptFalse: [ConfigStep] = []
    var scriptTrue: [ConfigStep] = []
    /// When set, the next `startConfig` call throws this instead of
    /// returning a step, then clears itself. Models a daemon/network failure
    /// without adding test-only state to the production RemoteSetupFlow type.
    var failNextStart: Error?
    /// Test seam for C2/NB-1: when set, every `continueConfig` call awaits
    /// this BEFORE recording the call or returning a step — so a test can
    /// suspend a walk mid-flight, start a second concurrent operation, and
    /// observe whether the two interleave, or cancel the suspended walk and
    /// observe the suspension abort (throwing) rather than needing an
    /// explicit release.
    var gate: (() async throws -> Void)?
    private(set) var calls: [String] = []
    private(set) var deletedRemotes: [String] = []
    private var cursorFalse = 0
    private var cursorTrue = 0

    func startConfig(name: String, type: String, askAll: Bool) async throws -> ConfigStep {
        calls.append("start(all:\(askAll))")
        if let failNextStart {
            self.failNextStart = nil
            throw failNextStart
        }
        if askAll { cursorTrue = 0 } else { cursorFalse = 0 }
        return next(askAll: askAll)
    }

    func continueConfig(
        name: String, type: String, state: String, result: String, askAll: Bool
    ) async throws -> ConfigStep {
        if let gate {
            try await gate()
        }
        calls.append("continue(\(state)=\(result))")
        return next(askAll: askAll)
    }

    func deletePartialRemote(name: String) async {
        // Recorded into `calls` too (not just `deletedRemotes`) so ordering
        // relative to start/continue calls is observable (I2).
        calls.append("delete(\(name))")
        deletedRemotes.append(name)
    }

    private func next(askAll: Bool) -> ConfigStep {
        if askAll {
            guard cursorTrue < scriptTrue.count else {
                // An over-walk past the scripted steps would otherwise
                // silently look correct (a bare .done) — flag it instead (S4).
                Issue.record("ScriptedConfigClient walked past the end of scriptTrue")
                return .done
            }
            defer { cursorTrue += 1 }
            return scriptTrue[cursorTrue]
        } else {
            guard cursorFalse < scriptFalse.count else {
                Issue.record("ScriptedConfigClient walked past the end of scriptFalse")
                return .done
            }
            defer { cursorFalse += 1 }
            return scriptFalse[cursorFalse]
        }
    }
}

/// One-shot rendezvous used by the concurrency tests. `hook()` (called from
/// inside the code under test, via `ScriptedConfigClient.gate`) signals
/// arrival and then suspends until EITHER `release()` is called, OR the
/// calling Task is cancelled — in which case it throws `CancellationError`,
/// mirroring how a real network call (URLSession's async APIs) behaves when
/// its Task is cancelled. That's exactly the mechanism NB-1's fix
/// (`walkChain?.cancel()`) relies on in production, so the test double must
/// model it rather than only ever unblocking via an explicit release.
/// `waitUntilArrived()` (called from the test body) suspends until `hook()`
/// has been entered. An `actor` so both sides can call it safely from
/// different Tasks without a hand-rolled lock.
private actor Gate {
    private var hasArrived = false
    private var arrivedContinuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func hook() async throws {
        hasArrived = true
        arrivedContinuation?.resume()
        arrivedContinuation = nil
        if !released {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if released {
                        continuation.resume()
                    } else {
                        releaseContinuation = continuation
                    }
                }
            } onCancel: {
                Task { await self.unblockForCancellation() }
            }
        }
        try Task.checkCancellation()
    }

    private func unblockForCancellation() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func waitUntilArrived() async {
        if hasArrived { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            arrivedContinuation = continuation
        }
    }

    /// Unblocks `hook()` normally (no cancellation, no throw). Used by
    /// `rewalkQueuedBehindAnotherRewalkNeverInterleavesItsCalls`, the one
    /// test below where both walks are meant to run to completion rather
    /// than be cancelled.
    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private func question(_ name: String, state: String, exclusive: Bool = false) -> ConfigQuestion {
    let json = #"""
    {"Name": "\#(name)", "Help": "", "Type": "string", "Required": false,
     "IsPassword": false, "Advanced": false, "Sensitive": false, "Hide": 0,
     "Exclusive": \#(exclusive), "Default": "", "DefaultStr": "", "Value": null}
    """#
    let option = try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
    return ConfigQuestion(option: option, state: state)
}

private func provider(_ name: String) -> Provider {
    let json = #"{"Name":"\#(name)","Description":"\#(name)","Prefix":"\#(name)","Options":[]}"#
    return try! JSONDecoder().decode(Provider.self, from: Data(json.utf8))
}

@Suite("RemoteSetupFlow", .serialized)
@MainActor
struct RemoteSetupFlowTests {

    @Test func batchesConsecutiveQuestionsIntoOnePage() async throws {
        let client = ScriptedConfigClient()
        // all:false on sftp asks nothing (a stub); all:true asks for real.
        client.scriptFalse = [.done]
        client.scriptTrue = [
            .question(question("host", state: "s0")),
            .question(question("user", state: "s1")),
            .question(question("port", state: "s2")),
            .advancedGate(question("config_fs_advanced", state: "s3")),
        ]
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()

        guard case .page(let page) = flow.phase else {
            Issue.record("expected .page, got \(flow.phase)"); return
        }
        #expect(page.questions.map(\.option.name) == ["host", "user", "port"])
        #expect(page.boundary == .advancedGate(question("config_fs_advanced", state: "s3")))
    }

    @Test func oauthBackendSkipsStraightToSignIn() async throws {
        let client = ScriptedConfigClient()
        let oauthQuestion = question("config_is_local", state: "*oauth-islocal,,,")
        client.scriptFalse = [.oauth(oauthQuestion)]
        let flow = RemoteSetupFlow(provider: provider("drive"), client: client)
        flow.name = "gdrive"
        await flow.begin()

        // .signingIn must carry the oauth question forward — losing it means
        // signIn() has no state to answer and the walk dead-ends (I3).
        #expect(flow.phase == .signingIn(oauthQuestion, askAll: false))
        // Basic mode for an OAuth backend must use all:false — using all:true
        // would surface client_id/client_secret, the fields users must leave blank.
        #expect(client.calls.first == "start(all:false)")
        // Nothing should have been deleted — the OAuth branch keeps its
        // walk rather than probing, discarding, and restarting.
        #expect(client.deletedRemotes.isEmpty)
    }

    @Test func signInAnswersOAuthQuestionAndFinishes() async throws {
        let client = ScriptedConfigClient()
        let oauthQuestion = question("config_is_local", state: "*oauth-islocal,,,")
        client.scriptFalse = [.oauth(oauthQuestion), .done]
        let flow = RemoteSetupFlow(provider: provider("drive"), client: client)
        flow.name = "gdrive"
        await flow.begin()
        #expect(flow.phase == .signingIn(oauthQuestion, askAll: false))

        await flow.signIn()

        #expect(client.calls.contains("continue(*oauth-islocal,,,=true)"))
        #expect(flow.phase == .finished)
    }

    @Test func signInCarriesTheAskAllValueFromWhenSigningInWasEntered() async throws {
        // NB-4: performSignIn() must use the askAll captured when .signingIn
        // was entered, not recompute it live. scriptTrue is deliberately
        // left empty: if signIn() wrongly used askAll:true (e.g. because the
        // user toggled "Show all options" while parked in .signingIn),
        // continueConfig would walk past the end of scriptTrue and
        // ScriptedConfigClient flags that as a test failure via Issue.record.
        let client = ScriptedConfigClient()
        let oauthQuestion = question("config_is_local", state: "*oauth-islocal,,,")
        client.scriptFalse = [.oauth(oauthQuestion), .done]
        let flow = RemoteSetupFlow(provider: provider("drive"), client: client)
        flow.name = "gdrive"
        await flow.begin()
        #expect(flow.phase == .signingIn(oauthQuestion, askAll: false))

        // Toggle "Show all options" while still parked in .signingIn — this
        // must not change which askAll signIn()'s continueConfig call uses.
        flow.showAllOptions = true

        await flow.signIn()

        #expect(flow.phase == .finished)
    }

    @Test func successfulOAuthCreateSurvivesALaterCancel() async throws {
        // C1: a successful create must not be deletable by a cancel that
        // lands afterward (e.g. Escape racing the dismiss-on-finish
        // transition in the UI).
        let client = ScriptedConfigClient()
        let oauthQuestion = question("config_is_local", state: "*oauth-islocal,,,")
        client.scriptFalse = [.oauth(oauthQuestion), .done]
        let flow = RemoteSetupFlow(provider: provider("drive"), client: client)
        flow.name = "gdrive"
        await flow.begin()
        await flow.signIn()
        #expect(flow.phase == .finished)

        await flow.cancel()

        #expect(client.deletedRemotes.isEmpty)
        #expect(flow.phase == .finished)
    }

    @Test func credentialBackendRestartsWithAskAllAfterEmptyProbe() async throws {
        let client = ScriptedConfigClient()
        // all:false on sftp asks nothing and writes a stub remote.
        client.scriptFalse = [.done]
        // all:true is what actually asks for the host.
        client.scriptTrue = [.question(question("host", state: "s0")), .done]
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()

        // Exact sequence, not just "contains": proves the stub was deleted
        // BEFORE the restart, not merely at some point during the walk (I2).
        #expect(client.calls == [
            "start(all:false)", "delete(myserver)", "start(all:true)", "continue(s0=)",
        ])
        // Landed on the last page (boundary .finished), not some garbage
        // intermediate state — and NOT yet .finished, since the user hasn't
        // reviewed the "host" field this walk discovered using a default.
        guard case .page(let page) = flow.phase, page.boundary == .finished else {
            Issue.record("expected a .finished-boundary page, got \(flow.phase)")
            return
        }
        #expect(page.questions.map(\.option.name) == ["host"])
    }

    @Test func finishedBoundaryPageSubmitAppliesRealAnswersOverDefaults() async throws {
        // S1 (proposed in fix round 1's supplement, then WITHDRAWN): a
        // `.finished`-boundary page's fields were answered by `answer(for:)`
        // during discovery, which falls back to rclone's default whenever
        // `answers` has nothing stored yet — the remote that exists at that
        // point is a defaults-built byproduct, not the user's remote.
        // submitPage() MUST delete and re-walk to apply what the user
        // actually typed; short-circuiting it (as S1 proposed) would keep
        // the placeholder remote and silently discard the user's answer.
        let client = ScriptedConfigClient()
        client.scriptFalse = [.done]
        client.scriptTrue = [.question(question("host", state: "s0")), .done]
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()

        guard case .page(let page) = flow.phase, page.boundary == .finished else {
            Issue.record("expected a .finished-boundary page, got \(flow.phase)")
            return
        }
        _ = page
        flow.answers["host"] = "example.com"

        await flow.submitPage()

        #expect(client.calls.contains("continue(s0=example.com)"))
        #expect(flow.phase == .finished)
    }

    @Test func replaysStoredAnswersOnEveryWalk() async throws {
        let client = ScriptedConfigClient()
        client.scriptFalse = [.done]
        client.scriptTrue = [
            .question(question("host", state: "s0")),
            .advancedGate(question("config_fs_advanced", state: "s1")),
        ]
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()
        flow.answers["host"] = "example.com"
        await flow.rewalk()

        #expect(client.calls.contains("continue(s0=example.com)"))
    }

    @Test func includeAdvancedTrueAnswersTheAdvancedGateWithTrue() async throws {
        // M1: pin that includeAdvanced actually reaches rclone as "true" —
        // this can silently never apply if the boundary-answering code path
        // stops threading it through.
        let client = ScriptedConfigClient()
        client.scriptFalse = [.done]
        client.scriptTrue = [
            .question(question("host", state: "s0")),
            .advancedGate(question("config_fs_advanced", state: "s1")),
            .done,
        ]
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()
        flow.includeAdvanced = true
        await flow.submitPage()

        #expect(client.calls.contains("continue(s1=true)"))
        #expect(flow.phase == .finished)
    }

    @Test func rewalkQueuedBehindAnotherRewalkNeverInterleavesItsCalls() async throws {
        // C2's core property, restored after fix round 3's rewrite of the
        // old interleaving test left only cancellation-based coverage:
        // two walks against the same remote must never interleave their
        // config/create calls. Neither walk here is cancelled — both queue
        // and run to completion — so this is the one test that actually
        // exercises `enqueue`'s `await previous?.value` chaining rather
        // than the cancellation path. Task 5 triggers a rewalk() on every
        // branching answer and Task 8 wires one to the "Show all options"
        // toggle; two rapid rewalks would race exactly like this if
        // `enqueue` didn't serialize them.
        //
        // Verified this test actually depends on that chaining by removing
        // `await previous?.value` from `enqueue` once, confirming this test
        // failed (the second rewalk's calls appeared before the first
        // finished), then restoring it — see fix round 4's report.
        let client = ScriptedConfigClient()
        client.scriptFalse = [.done]
        client.scriptTrue = [
            .question(question("host", state: "s0")),
            .question(question("user", state: "s1")),
            .done,
        ]
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()
        guard case .page = flow.phase else {
            Issue.record("expected .page, got \(flow.phase)"); return
        }
        let callsBeforeRewalks = client.calls.count

        let gate = Gate()
        var continueCallsSinceGateInstalled = 0
        client.gate = {
            continueCallsSinceGateInstalled += 1
            // Suspend the FIRST rewalk's SECOND continueConfig call
            // (answering "user"), so the second rewalk() starts genuinely
            // mid-walk rather than before the first one begins.
            if continueCallsSinceGateInstalled == 2 {
                try await gate.hook()
            }
        }

        async let firstRewalk: Void = flow.rewalk()
        await gate.waitUntilArrived()
        let callsWhileFirstIsSuspended = client.calls.count

        async let secondRewalk: Void = flow.rewalk()
        // Give the second rewalk's task every opportunity to run if
        // walkChain were (incorrectly) not enforcing exclusion.
        for _ in 0..<5 { await Task.yield() }
        #expect(client.calls.count == callsWhileFirstIsSuspended)

        await gate.release()
        _ = await (firstRewalk, secondRewalk)

        // The two walks' calls appear as two clean, non-interleaved runs —
        // not, e.g., both walks' deletes followed by both walks' starts.
        let afterBothRewalks = Array(client.calls[callsBeforeRewalks...])
        let oneWalk = ["delete(myserver)", "start(all:true)", "continue(s0=)", "continue(s1=)"]
        #expect(afterBothRewalks == oneWalk + oneWalk)
    }

    @Test func cancelDeletesThePartialRemote() async throws {
        let client = ScriptedConfigClient()
        client.scriptFalse = [.done]
        client.scriptTrue = [.question(question("host", state: "s0")), .done]
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()
        // I1: begin() on a credential backend already deletes the empty-probe
        // stub, so asserting `deletedRemotes.contains` is vacuously true
        // before cancel() ever runs. Capture the count first and require
        // cancel() to strictly increase it.
        let deletesBeforeCancel = client.deletedRemotes.count

        await flow.cancel()

        #expect(client.deletedRemotes.count > deletesBeforeCancel)
    }

    @Test func failedWalkDeletesThePartialRemote() async throws {
        // S5: the failure is driven through the test double, not a
        // production-only seam on RemoteSetupFlow.
        struct Boom: Error {}
        let client = ScriptedConfigClient()
        client.failNextStart = Boom()
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()

        guard case .failed = flow.phase else {
            Issue.record("expected .failed, got \(flow.phase)"); return
        }
        #expect(client.deletedRemotes.contains("myserver"))
    }

    @Test func walkAbortsAfterTooManyStepsInsteadOfLoopingForever() async throws {
        // S3: a daemon that keeps returning the same state must not spin the
        // walk forever hammering rclone. 205 identical entries comfortably
        // exceeds the 200-step cap without running past the script's end
        // (which ScriptedConfigClient itself now flags as a test failure).
        let client = ScriptedConfigClient()
        let stuckQuestion = question("host", state: "stuck")
        client.scriptFalse = Array(repeating: ConfigStep.question(stuckQuestion), count: 205)
        client.scriptTrue = client.scriptFalse
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()

        guard case .failed = flow.phase else {
            Issue.record("expected .failed, got \(flow.phase)"); return
        }
    }

    @Test func cancelAbortsAnInFlightSubmitInsteadOfWaitingForIt() async throws {
        // C2 + NB-1: cancel() must ABORT the in-flight walk, not politely
        // wait for it to finish first — waiting is exactly what left the
        // Cancel button inert during a blocking signIn() (NB-1). This proves
        // the same abort-not-wait behavior for a submitPage() walk: cancel()
        // must not let it run to completion before taking its own turn.
        let client = ScriptedConfigClient()
        client.scriptFalse = [.done]
        client.scriptTrue = [
            .question(question("host", state: "s0")),
            .question(question("user", state: "s1")),
            .done,
        ]
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()
        guard case .page = flow.phase else {
            Issue.record("expected .page, got \(flow.phase)"); return
        }

        let gate = Gate()
        var continueCallsSinceGateInstalled = 0
        client.gate = {
            continueCallsSinceGateInstalled += 1
            // Suspend the SECOND continueConfig call of the submit's
            // re-walk (the first answers "host"), so cancel() lands
            // genuinely mid-walk rather than before the walk begins.
            if continueCallsSinceGateInstalled == 2 {
                try await gate.hook()
            }
        }

        async let submitTask: Void = flow.submitPage()
        await gate.waitUntilArrived()
        let deletesBeforeCancel = client.deletedRemotes.count

        // cancel() must resolve on its own — this test never calls
        // gate.release() — proving it aborted the blocking continueConfig
        // call via cancellation rather than waiting for submit to finish.
        await flow.cancel()
        _ = await submitTask

        #expect(flow.phase == .naming)
        // The aborted submit quietly stopped without reaching .finished (so
        // it never cleared the cleanup target itself); cancel()'s own
        // cleanup is what deletes the remote.
        #expect(client.deletedRemotes.count > deletesBeforeCancel)
    }

    @Test func exclusiveAnswerTriggersRewalk() async throws {
        // s3's `provider` option is Exclusive: answering it changes which
        // fields follow (AWS vs. Wasabi ask for different things), so the
        // page the walk already rendered is stale and must be re-walked.
        let client = ScriptedConfigClient()
        // all:false on s3 asks nothing and writes a stub, same as sftp.
        client.scriptFalse = [.done]
        client.scriptTrue = [
            .question(question("provider", state: "s0", exclusive: true)),
            .advancedGate(question("config_fs_advanced", state: "s1")),
        ]
        let flow = RemoteSetupFlow(provider: provider("s3"), client: client)
        flow.name = "bucket"
        await flow.begin()

        let before = client.calls.filter { $0.hasPrefix("start(") }.count
        await flow.answerChanged(question("provider", state: "s0", exclusive: true), to: "AWS")
        let after = client.calls.filter { $0.hasPrefix("start(") }.count

        #expect(after > before)
        #expect(flow.answers["provider"] == "AWS")
    }

    @Test func nonExclusiveAnswerDoesNotRewalk() async throws {
        let client = ScriptedConfigClient()
        client.scriptFalse = [.done]
        client.scriptTrue = [
            .question(question("access_key_id", state: "s0")),
            .advancedGate(question("config_fs_advanced", state: "s1")),
        ]
        let flow = RemoteSetupFlow(provider: provider("s3"), client: client)
        flow.name = "bucket"
        await flow.begin()

        let before = client.calls.filter { $0.hasPrefix("start(") }.count
        await flow.answerChanged(question("access_key_id", state: "s0"), to: "AKIA")
        let after = client.calls.filter { $0.hasPrefix("start(") }.count

        #expect(after == before)
        #expect(flow.answers["access_key_id"] == "AKIA")
    }

    @Test func rewalkPreservesUnrelatedAnswers() async throws {
        let client = ScriptedConfigClient()
        client.scriptFalse = [.done]
        client.scriptTrue = [
            .question(question("provider", state: "s0", exclusive: true)),
            .advancedGate(question("config_fs_advanced", state: "s1")),
        ]
        let flow = RemoteSetupFlow(provider: provider("s3"), client: client)
        flow.name = "bucket"
        await flow.begin()
        flow.answers["access_key_id"] = "AKIA"

        await flow.answerChanged(question("provider", state: "s0", exclusive: true), to: "Wasabi")

        #expect(flow.answers["access_key_id"] == "AKIA")
        #expect(flow.answers["provider"] == "Wasabi")
    }

    @Test func cancelDuringSignInAbortsTheBlockingOAuthWaitAndCleansUp() async throws {
        // NB-1: the Cancel button in .signingIn must actually work. Before
        // this fix, cancel() queued behind signIn()'s blocking continueConfig
        // call — which can legitimately hang forever waiting on the user's
        // browser — and never got a turn. cancel() must abort that in-flight
        // call instead of waiting for it.
        let client = ScriptedConfigClient()
        let oauthQuestion = question("config_is_local", state: "*oauth-islocal,,,")
        client.scriptFalse = [.oauth(oauthQuestion)]
        let flow = RemoteSetupFlow(provider: provider("drive"), client: client)
        flow.name = "gdrive"
        await flow.begin()
        #expect(flow.phase == .signingIn(oauthQuestion, askAll: false))

        let gate = Gate()
        client.gate = { try await gate.hook() }

        async let signInTask: Void = flow.signIn()
        await gate.waitUntilArrived()

        // cancel() must resolve on its own — this test never calls
        // gate.release() — proving it aborted signIn()'s blocking wait
        // rather than waiting for it (which, absent a browser completing
        // OAuth, could be forever).
        await flow.cancel()
        _ = await signInTask

        #expect(flow.phase == .naming)
        #expect(client.deletedRemotes.contains("gdrive"))
    }
}
