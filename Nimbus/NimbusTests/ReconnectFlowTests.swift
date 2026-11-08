import Testing
import Foundation
import RcloneKit
@testable import Nimbus

@MainActor
private final class ScriptedReconnectClient: RemoteReconnectDriving {
    var steps: [ConfigStep]
    private(set) var answers: [(state: String, result: String)] = []
    var failure: Error?

    init(_ steps: [ConfigStep]) { self.steps = steps }

    func startUpdate(name: String) async throws -> ConfigStep {
        if let failure { throw failure }
        return steps.removeFirst()
    }

    func continueUpdate(name: String, state: String, result: String) async throws -> ConfigStep {
        answers.append((state, result))
        return steps.isEmpty ? .done : steps.removeFirst()
    }
}

private func option(_ name: String) -> ProviderOption {
    let json = #"{"Name":"\#(name)","Help":"","Type":"string","Required":false,"IsPassword":false,"Advanced":false,"Sensitive":false,"Hide":0,"Exclusive":false,"Default":"","DefaultStr":"","Value":null}"#
    return try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
}

private func q(_ name: String, _ state: String) -> ConfigQuestion {
    ConfigQuestion(option: option(name), state: state)
}

@Suite("ReconnectFlow")
@MainActor
struct ReconnectFlowTests {
    @Test func driveWalkAnswersKnownQuestionsAndStopsAfterBrowser() async {
        let client = ScriptedReconnectClient([
            .question(q("config_shared_client_id", "client_id_warning")),
            .oauth(q("config_refresh_token", "*oauth-confirm,teamdrive,oauth,")),
            .oauth(q("config_is_local", "*oauth-islocal,teamdrive,oauth,")),
            // Asked after sign-in; must NOT be answered.
            .question(q("config_change_team_drive", "teamdrive_config")),
        ])
        let flow = ReconnectFlow(remoteName: "gd", client: client)
        await flow.signIn()
        #expect(flow.phase == .finished)
        #expect(client.answers.map(\.result) == ["true", "true", "true"])
        // The post-sign-in question comes back from the browser call and is
        // never answered: exactly three answers, the last being the browser.
        #expect(client.answers.count == 3)
        #expect(client.answers.last?.state == "*oauth-islocal,teamdrive,oauth,")
        #expect(!client.answers.contains { $0.state == "teamdrive_config" })
    }

    @Test func unknownQuestionBeforeSignInStopsWithoutAnswering() async {
        let client = ScriptedReconnectClient([.question(q("client_id", "*all-set,0"))])
        let flow = ReconnectFlow(remoteName: "x", client: client)
        await flow.signIn()
        #expect(flow.phase == .needsSettings)
        #expect(client.answers.isEmpty)
    }

    @Test func immediateDoneFinishes() async {
        let flow = ReconnectFlow(remoteName: "x", client: ScriptedReconnectClient([.done]))
        await flow.signIn()
        #expect(flow.phase == .finished)
    }

    @Test func rcloneErrorSurfacesAsFailed() async {
        let client = ScriptedReconnectClient([])
        client.failure = RcloneError.requestFailed(status: 200, message: "didn't find section")
        let flow = ReconnectFlow(remoteName: "x", client: client)
        await flow.signIn()
        guard case .failed = flow.phase else { Issue.record("expected failed, got \(flow.phase)"); return }
    }

    @Test func cancelReturnsToReady() {
        let flow = ReconnectFlow(remoteName: "x", client: ScriptedReconnectClient([]))
        flow.cancel()
        #expect(flow.phase == .ready)
    }
}
