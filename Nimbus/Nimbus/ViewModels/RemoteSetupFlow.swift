import Foundation
import Observation
import RcloneKit

/// The three config-machine calls the flow needs, abstracted so tests can
/// script a walk without a live rclone daemon.
@MainActor
protocol RemoteConfigDriving {
    func startConfig(name: String, type: String, askAll: Bool) async throws -> ConfigStep
    func continueConfig(
        name: String, type: String, state: String, result: String, askAll: Bool
    ) async throws -> ConfigStep
    func deletePartialRemote(name: String) async
}

extension RcloneClient: RemoteConfigDriving {}

/// A run of consecutive plain questions plus whatever ended the run.
struct ConfigPage: Equatable {
    enum Boundary: Equatable {
        case oauth(ConfigQuestion)
        case advancedGate(ConfigQuestion)
        case finished
    }
    let questions: [ConfigQuestion]
    let boundary: Boundary
}

/// Drives rclone's interactive config machine for one new remote.
///
/// Every walk restarts from `startConfig` and replays `answers`, so the walk
/// is idempotent and re-walking after a branching answer is an ordinary call
/// rather than a special path. The cost is a handful of loopback HTTP calls
/// to a local daemon.
@Observable
@MainActor
final class RemoteSetupFlow {
    enum Phase: Equatable {
        case naming
        case loading
        case page(ConfigPage)
        case signingIn
        case creating
        case finished
        case failed(String)
    }

    let provider: Provider
    var phase: Phase = .naming
    var name = ""
    var answers: [String: String] = [:]
    var showAllOptions = false
    var includeAdvanced = false

    /// Test seam: forces the next walk to throw.
    var injectedFailure: Error?

    private let client: any RemoteConfigDriving
    /// Nil until the first probe tells us which kind of backend this is.
    private(set) var isOAuthBackend: Bool?
    /// True once a call has written the partial remote rclone creates on
    /// `config/create` — gates cleanup so we never delete someone else's remote.
    private var partialRemoteExists = false

    init(provider: Provider, client: any RemoteConfigDriving) {
        self.provider = provider
        self.client = client
    }

    /// `all:false` is safe only for OAuth backends. For credential backends
    /// it asks nothing and leaves a stub remote, so we probe once, throw the
    /// stub away, and restart asking everything.
    private var askAll: Bool {
        if showAllOptions { return true }
        return isOAuthBackend == false
    }

    func begin() async {
        phase = .loading
        do {
            let first = try await start(askAll: false)
            switch first {
            case .oauth:
                isOAuthBackend = true
                await advance(from: first, askAll: false)
            default:
                isOAuthBackend = false
                await cleanUpPartialRemote()
                let restarted = try await start(askAll: true)
                await advance(from: restarted, askAll: true)
            }
        } catch {
            await fail(error)
        }
    }

    /// Restarts the walk from scratch, replaying `answers`. Called after a
    /// branching (`Exclusive`) answer changes, or when a mode toggle flips.
    func rewalk() async {
        phase = .loading
        do {
            await cleanUpPartialRemote()
            let first = try await start(askAll: askAll)
            await advance(from: first, askAll: askAll)
        } catch {
            await fail(error)
        }
    }

    /// Answers the current page's boundary and walks on. Ends in `.finished`
    /// (remote created), `.signingIn`, or the next `.page`.
    func submitPage() async {
        guard case .page(let page) = phase else { return }
        phase = .creating
        do {
            let resumed = try await replay(askAll: askAll, answeringBoundaryOf: page)
            await advance(from: resumed, askAll: askAll)
        } catch {
            await fail(error)
        }
    }

    func cancel() async {
        await cleanUpPartialRemote()
        phase = .naming
    }

    // MARK: - Walk

    private func start(askAll: Bool) async throws -> ConfigStep {
        // Set before any throw: rclone writes the partial remote on the first
        // config/create call, so a call that fails mid-flight may still have
        // created the stub. Assume it exists and attempt cleanup — deleting a
        // remote that was never created is a harmless no-op, leaking a stub is not.
        partialRemoteExists = true
        if let injectedFailure { throw injectedFailure }
        return try await client.startConfig(name: name, type: provider.name, askAll: askAll)
    }

    /// Consumes plain questions into a page, stopping at the first boundary.
    /// Does NOT answer the boundary — that is `submitPage`'s job — so simply
    /// rendering a page never creates the remote.
    private func advance(from first: ConfigStep, askAll: Bool) async {
        var collected: [ConfigQuestion] = []
        var step = first
        do {
            while true {
                switch step {
                case .question(let q):
                    collected.append(q)
                    step = try await client.continueConfig(
                        name: name, type: provider.name, state: q.state,
                        result: answer(for: q), askAll: askAll
                    )
                case .oauth(let q):
                    phase = collected.isEmpty
                        ? .signingIn
                        : .page(ConfigPage(questions: collected, boundary: .oauth(q)))
                    return
                case .advancedGate(let q):
                    phase = .page(ConfigPage(questions: collected, boundary: .advancedGate(q)))
                    return
                case .done:
                    phase = collected.isEmpty
                        ? .finished
                        : .page(ConfigPage(questions: collected, boundary: .finished))
                    return
                }
            }
        } catch {
            await fail(error)
        }
    }

    /// Walks from the start replaying answers, then answers the boundary the
    /// given page stopped at and returns the step after it.
    private func replay(askAll: Bool, answeringBoundaryOf page: ConfigPage) async throws -> ConfigStep {
        await cleanUpPartialRemote()
        var step = try await start(askAll: askAll)
        while case .question(let q) = step {
            step = try await client.continueConfig(
                name: name, type: provider.name, state: q.state,
                result: answer(for: q), askAll: askAll
            )
        }
        switch step {
        case .advancedGate(let q):
            return try await client.continueConfig(
                name: name, type: provider.name, state: q.state,
                result: includeAdvanced ? "true" : "false", askAll: askAll
            )
        case .oauth, .done, .question:
            return step
        }
    }

    private func answer(for question: ConfigQuestion) -> String {
        answers[question.option.name] ?? question.option.defaultValue
    }

    private func fail(_ error: Error) async {
        await cleanUpPartialRemote()
        phase = .failed(NimbusError.classify(error).message)
    }

    private func cleanUpPartialRemote() async {
        guard partialRemoteExists, !name.isEmpty else { return }
        await client.deletePartialRemote(name: name)
        partialRemoteExists = false
    }
}
