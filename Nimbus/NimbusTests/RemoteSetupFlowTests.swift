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

    @Test func finishedBoundaryPageSubmitDoesNotDeleteAndRecreate() async throws {
        // S1: once advance() reaches `.done` with collected fields, rclone
        // has already fully written the remote. submitPage() must NOT
        // delete-and-rewalk to "finish" it — if that rewalk failed partway,
        // the user's already-complete remote would simply be gone.
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
        let callsBeforeSubmit = client.calls.count

        await flow.submitPage()

        #expect(flow.phase == .finished)
        // No further client calls at all — confirms no delete+recreate ran.
        #expect(client.calls.count == callsBeforeSubmit)
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
}
