import Testing
import Foundation
import RcloneKit
@testable import Nimbus

/// Scripts a sequence of `config/create` replies so the flow can be walked
/// without a live rclone. Mirrors the fixture style in ProviderPickerTests:
/// RcloneKit models are decode-only.
@MainActor
private final class ScriptedConfigClient: RemoteConfigDriving {
    var script: [ConfigStep] = []
    private(set) var calls: [String] = []
    private(set) var deletedRemotes: [String] = []
    private var cursor = 0

    func startConfig(name: String, type: String, askAll: Bool) async throws -> ConfigStep {
        calls.append("start(all:\(askAll))")
        cursor = 0
        return next()
    }

    func continueConfig(
        name: String, type: String, state: String, result: String, askAll: Bool
    ) async throws -> ConfigStep {
        calls.append("continue(\(state)=\(result))")
        return next()
    }

    func deletePartialRemote(name: String) async {
        deletedRemotes.append(name)
    }

    private func next() -> ConfigStep {
        guard cursor < script.count else { return .done }
        defer { cursor += 1 }
        return script[cursor]
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
        client.script = [
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
        client.script = [.oauth(question("config_is_local", state: "*oauth-islocal,,,"))]
        let flow = RemoteSetupFlow(provider: provider("drive"), client: client)
        flow.name = "gdrive"
        await flow.begin()

        #expect(flow.phase == .signingIn)
        // Basic mode for an OAuth backend must use all:false — using all:true
        // would surface client_id/client_secret, the fields users must leave blank.
        #expect(client.calls.first == "start(all:false)")
    }

    @Test func credentialBackendRestartsWithAskAllAfterEmptyProbe() async throws {
        let client = ScriptedConfigClient()
        // all:false on sftp asks nothing and would write a stub remote.
        client.script = [.done]
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()

        #expect(client.calls.contains("start(all:false)"))
        #expect(client.calls.contains("start(all:true)"))
        // The stub written by the probe must be deleted before restarting.
        #expect(client.deletedRemotes.contains("myserver"))
    }

    @Test func replaysStoredAnswersOnEveryWalk() async throws {
        let client = ScriptedConfigClient()
        client.script = [
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

    @Test func cancelDeletesThePartialRemote() async throws {
        let client = ScriptedConfigClient()
        client.script = [.question(question("host", state: "s0")), .done]
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        await flow.begin()
        await flow.cancel()

        #expect(client.deletedRemotes.contains("myserver"))
    }

    @Test func failedWalkDeletesThePartialRemote() async throws {
        struct Boom: Error {}
        let client = ScriptedConfigClient()
        let flow = RemoteSetupFlow(provider: provider("sftp"), client: client)
        flow.name = "myserver"
        flow.injectedFailure = Boom()
        await flow.begin()

        guard case .failed = flow.phase else {
            Issue.record("expected .failed, got \(flow.phase)"); return
        }
        #expect(client.deletedRemotes.contains("myserver"))
    }
}
