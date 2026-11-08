import Foundation
import Observation
import RcloneKit

/// The two `config/update` calls signing in again needs, abstracted so tests
/// can script a walk without a live daemon.
@MainActor
protocol RemoteReconnectDriving {
    func startUpdate(name: String) async throws -> ConfigStep
    func continueUpdate(name: String, state: String, result: String) async throws -> ConfigStep
}

extension RcloneClient: RemoteReconnectDriving {}

/// Signs an existing OAuth cloud in again by walking rclone's `config/update`
/// machine (verified on rclone 1.76: drive goes client-id warning →
/// `*oauth-confirm` "Token already configured - replace it?" →
/// `*oauth-islocal` browser hand-off).
///
/// It answers only the questions it understands, and stops as soon as the
/// browser step returns. rclone persists after every call, so the new token
/// is saved by then, and anything rclone asks afterwards (OneDrive's drive
/// picker, for one) is left exactly as it was. Any question it does not
/// recognise before sign-in ends the walk with `.needsSettings` rather than
/// guessing an answer that could change the cloud's configuration.
@Observable
@MainActor
final class ReconnectFlow {
    enum Phase: Equatable {
        case ready
        case preparing
        case waitingForBrowser
        case finished
        case needsSettings
        case failed(String)
    }

    let remoteName: String
    private(set) var phase: Phase = .ready
    private let client: any RemoteReconnectDriving
    private var walk: Task<Void, Never>?
    private static let maxSteps = 12

    init(remoteName: String, client: any RemoteReconnectDriving) {
        self.remoteName = remoteName
        self.client = client
    }

    /// The answer Nimbus gives on the user's behalf, or nil when the question
    /// needs a human (the walk then stops with `.needsSettings`).
    static func automaticAnswer(for question: ConfigQuestion) -> String? {
        if question.state.hasPrefix("*oauth-islocal") { return "true" }
        switch question.option.name {
        case "config_refresh_token": return "true"     // replace the stale token
        case "config_shared_client_id": return "true"  // keep the client id it already uses
        default: return nil
        }
    }

    func signIn() async {
        walk?.cancel()
        let task = Task { await performWalk() }
        walk = task
        await task.value
    }

    func cancel() {
        walk?.cancel()
        walk = nil
        phase = .ready
    }

    private func performWalk() async {
        phase = .preparing
        do {
            var step = try await client.startUpdate(name: remoteName)
            for _ in 0..<Self.maxSteps {
                try Task.checkCancellation()
                let question: ConfigQuestion
                switch step {
                case .done:
                    phase = .finished
                    return
                case .question(let q), .oauth(let q), .advancedGate(let q):
                    question = q
                }
                guard let answer = Self.automaticAnswer(for: question) else {
                    phase = .needsSettings
                    return
                }
                if question.state.hasPrefix("*oauth-islocal") {
                    phase = .waitingForBrowser
                    // Blocks until the browser callback lands; the token is
                    // saved when it returns. Stop here on purpose.
                    _ = try await client.continueUpdate(
                        name: remoteName, state: question.state, result: answer)
                    try Task.checkCancellation()
                    phase = .finished
                    return
                }
                step = try await client.continueUpdate(
                    name: remoteName, state: question.state, result: answer)
            }
            phase = .failed("Sign-in didn't finish. Try again, or edit the cloud's settings.")
        } catch is CancellationError {
            phase = .ready
        } catch {
            if Task.isCancelled { phase = .ready; return }
            phase = .failed(error.localizedDescription)
        }
    }
}
