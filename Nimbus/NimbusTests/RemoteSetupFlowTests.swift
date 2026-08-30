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
    /// Test seam for C2: when set, every `continueConfig` call awaits this
    /// BEFORE recording the call or returning a step — so a test can
    /// suspend a walk mid-flight, start a second concurrent operation, and
    /// observe whether the two interleave.
    var gate: (() async -> Void)?
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
            await gate()
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

/// One-shot rendezvous used by the C2 concurrency test. `hook()` (called
/// from inside the code under test, via `ScriptedConfigClient.gate`) signals
/// arrival and then suspends until `release()` is called; `waitUntilArrived()`
/// (called from the test body) suspends until `hook()` has been entered. An
/// `actor` so both sides can call it safely from different Tasks without a
/// hand-rolled lock.
private actor Gate {
    private var hasArrived = false
    private var arrivedContinuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func hook() async {
        hasArrived = true
        arrivedContinuation?.resume()
        arrivedContinuation = nil
        if released { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            releaseContinuation = continuation
        }
    }

    func waitUntilArrived() async {
        if hasArrived { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            arrivedContinuation = continuation
        }
    }

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
        #expect(flow.phase == .signingIn(oauthQuestion))
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
        #expect(flow.phase == .signingIn(oauthQuestion))

        await flow.signIn()

        #expect(client.calls.contains("continue(*oauth-islocal,,,=true)"))
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

    @Test func cancelQueuedBehindAnInFlightSubmitNeverInterleavesAndNoOpsOnceFinished() async throws {
        // C2: a Cancel landing while a submit is still mid-flight must not
        // interleave its calls with the submit's, and must not delete a
        // remote the submit went on to finish creating. walkChain (enqueue)
        // is what guarantees this — this drives it under real concurrency
        // (two genuinely in-flight Tasks via a suspension gate), not merely
        // sequential awaits, which would trivially never interleave on
        // their own.
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
            // re-walk (the first answers "host"), so cancel() is started
            // genuinely mid-walk rather than before the walk begins.
            if continueCallsSinceGateInstalled == 2 {
                await gate.hook()
            }
        }

        async let submitTask: Void = flow.submitPage()
        await gate.waitUntilArrived()
        let callsWhileSuspended = client.calls.count
        let deletesBeforeCancel = client.deletedRemotes.count

        async let cancelTask: Void = flow.cancel()
        // Give cancel's task every opportunity to run if walkChain were
        // (incorrectly) not enforcing exclusion.
        for _ in 0..<5 { await Task.yield() }
        #expect(client.calls.count == callsWhileSuspended)

        await gate.release()
        _ = await (submitTask, cancelTask)

        #expect(flow.phase == .finished)
        // cancel() only got its turn after submit had already resolved to
        // .finished, so its own guard made it a no-op — no delete beyond
        // whatever the submit itself made along the way.
        #expect(client.deletedRemotes.count == deletesBeforeCancel)
    }
}
