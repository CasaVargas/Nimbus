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
///
/// A walk is not local state — it creates and deletes a remote in
/// rclone.conf via HTTP calls to rclone. Two walks running at once (e.g. a
/// Cancel landing while a submit is still mid-flight) would interleave those
/// calls and corrupt each other's result, so every entry point below is
/// serialized behind `walkChain` (see `enqueue`).
@Observable
@MainActor
final class RemoteSetupFlow {
    enum Phase: Equatable {
        case naming
        case loading
        case page(ConfigPage)
        /// Waiting on rclone's browser OAuth round-trip. Carries the
        /// `*oauth-islocal` question so `signIn()` has the state to answer.
        case signingIn(ConfigQuestion)
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

    /// Serializes walks: each call chains behind whichever one is already
    /// running, so `config/create`/delete calls from two walks can never
    /// interleave. Entry points stay plain `async` methods and simply await
    /// their own turn — sequential callers (including the existing tests)
    /// see no behavior change.
    private var walkChain: Task<Void, Never>?

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

    // MARK: - Entry points

    func begin() async {
        await enqueue { await self.performBegin() }
    }

    /// Restarts the walk from scratch, replaying `answers`. Called after a
    /// branching (`Exclusive`) answer changes, or when a mode toggle flips.
    func rewalk() async {
        await enqueue { await self.performRewalk() }
    }

    /// Answers the current page's boundary and walks on. Ends in `.finished`
    /// (remote created), `.signingIn`, or the next `.page`.
    func submitPage() async {
        await enqueue { await self.performSubmitPage() }
    }

    /// Answers rclone's `config_is_local` question with "true", which makes
    /// rclone bind 127.0.0.1:53682, open the user's browser, and BLOCK until
    /// the OAuth callback arrives. Nimbus is not sandboxed, so rclone owning
    /// the browser handoff works. The call can legitimately take minutes.
    func signIn() async {
        await enqueue { await self.performSignIn() }
    }

    func cancel() async {
        await enqueue { await self.performCancel() }
    }

    // MARK: - Serialization

    private func enqueue(_ body: @escaping @MainActor () async -> Void) async {
        let previous = walkChain
        let task = Task { @MainActor in
            await previous?.value
            await body()
        }
        walkChain = task
        await task.value
    }

    // MARK: - Walk bodies (run only once it's their turn on walkChain)

    private func performBegin() async {
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

    private func performRewalk() async {
        phase = .loading
        do {
            await cleanUpPartialRemote()
            let first = try await start(askAll: askAll)
            await advance(from: first, askAll: askAll)
        } catch {
            await fail(error)
        }
    }

    private func performSubmitPage() async {
        guard case .page = phase else { return }
        phase = .creating
        do {
            let resumed = try await replayAnsweringBoundary(askAll: askAll)
            await advance(from: resumed, askAll: askAll)
        } catch {
            await fail(error)
        }
    }

    private func performSignIn() async {
        guard case .signingIn(let question) = phase else { return }
        do {
            let next = try await client.continueConfig(
                name: name, type: provider.name, state: question.state,
                result: "true", askAll: askAll
            )
            await advance(from: next, askAll: askAll)
        } catch {
            await fail(error)
        }
    }

    private func performCancel() async {
        // A remote the machine already reported `.done` on is the user's
        // data, not walk-in-progress scaffolding — never delete it, even if
        // a stray cancel lands after completion (e.g. Escape racing the
        // dismiss-on-finish transition).
        guard phase != .finished else { return }
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
                        ? .signingIn(q)
                        : .page(ConfigPage(questions: collected, boundary: .oauth(q)))
                    return
                case .advancedGate(let q):
                    phase = .page(ConfigPage(questions: collected, boundary: .advancedGate(q)))
                    return
                case .done:
                    if collected.isEmpty {
                        // Nothing new was collected on the way here, so
                        // every field this walk touched (if any) already
                        // carried a real, user-supplied answer rather than a
                        // placeholder default. The remote is genuinely
                        // complete: clear the cleanup flag BEFORE publishing
                        // `.finished`, so a cancel racing the finish
                        // transition can never delete a remote the user just
                        // successfully created.
                        partialRemoteExists = false
                        phase = .finished
                    } else {
                        // This batch's fields were answered via `answer(for:)`,
                        // which falls back to rclone's default whenever
                        // `answers` has nothing stored yet — i.e. the user
                        // hasn't reviewed this page. The remote that exists
                        // right now holds those defaults, not the user's
                        // intent, so leave partialRemoteExists set: a cancel
                        // from this page must still delete it.
                        phase = .page(ConfigPage(questions: collected, boundary: .finished))
                    }
                    return
                }
            }
        } catch {
            await fail(error)
        }
    }

    /// Walks from the start replaying `answers`, then answers whatever
    /// boundary that walk lands on and returns the step after it. Always
    /// re-derives the boundary from this fresh walk rather than trusting the
    /// `.page` that led here — that page's own `.boundary` can be stale (it
    /// may have been probed with placeholder answers), so this walk is the
    /// only source of truth.
    private func replayAnsweringBoundary(askAll: Bool) async throws -> ConfigStep {
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
            // OAuth can't be auto-answered here — it needs a live browser
            // round-trip via signIn() — so hand it back unanswered. .done
            // and .question (the while loop's own exit values) just pass
            // the walk's natural end state back up to advance().
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
