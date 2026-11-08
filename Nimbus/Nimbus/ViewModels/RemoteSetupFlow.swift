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

/// Caps a single walk at the same number of turns the design's own rclone
/// walk harness uses. A plain top-level constant (not a member of the
/// `@MainActor` class below) so `StuckWalkError`, which is not actor-
/// isolated, can read it without a cross-actor hop.
private let maxWalkSteps = 200

/// Safety valve against a daemon that never advances the walk (e.g. keeps
/// returning the same state) — thrown once a walk exceeds `maxWalkSteps`
/// rather than hammering rclone forever.
private struct StuckWalkError: LocalizedError {
    var errorDescription: String? {
        "The remote setup walk did not finish after \(maxWalkSteps) steps."
    }
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
        /// `*oauth-islocal` question so `signIn()` has the state to answer,
        /// and the `askAll` the walk used to reach this state — `signIn()`
        /// must reuse it rather than recompute the live `askAll` property,
        /// or toggling "Show all options" while parked here would pair the
        /// original `all:false` start with an `all:true` continue (NB-4).
        case signingIn(ConfigQuestion, askAll: Bool)
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

    private let client: any RemoteConfigDriving
    /// Nil until the first probe tells us which kind of backend this is.
    private(set) var isOAuthBackend: Bool?
    /// The name a `config/create` call actually used the moment it wrote
    /// rclone's partial remote stub, or nil once that stub has been cleaned
    /// up (or never existed). Recording the name itself — not just a bool —
    /// means cleanup always targets the remote a call actually touched, even
    /// if `name` is edited afterward, instead of whatever `name` currently
    /// holds.
    private var partialRemoteName: String?

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
        // isOAuthBackend is nil only during the initial probe in begin(),
        // which always passes askAll:false explicitly rather than consulting
        // this property, so the nil branch is unreachable in practice — but
        // false is the only safe default if it ever were hit: true would ask
        // for client_id/client_secret before we even know which kind of
        // backend this is.
        guard let isOAuthBackend else { return false }
        return !isOAuthBackend
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

    /// Records an answer. Answers to `Exclusive` options branch the remaining
    /// question set, so the current page is stale and the walk restarts;
    /// everything else just updates the dictionary in place.
    func answerChanged(_ question: ConfigQuestion, to value: String) async {
        answers[question.option.name] = value
        guard question.option.exclusive else { return }
        await rewalk()
    }

    func cancel() async {
        // Abort the in-flight walk before queueing our own turn. Without
        // this, cancel() waits behind a signIn() that rclone can block on
        // for minutes — or forever, if the user never finishes in the
        // browser — leaving the Cancel button inert, which the spec
        // explicitly forbids (NB-1). Serialization still holds: we cancel,
        // then wait for the aborted walk to unwind before doing our own
        // cleanup, so no delete races a live create.
        walkChain?.cancel()
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
            // Clean up any stub left by a prior begin()/rewalk() before
            // starting fresh, matching performRewalk's same defensive
            // cleanup. Unreachable today (nothing currently calls begin()
            // a second time on the same flow instance), but closes the gap
            // before it can be reached — e.g. a second begin() from
            // .page/.signingIn after a rename (NB-3).
            await cleanUpPartialRemote()
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
        // This deliberately does NOT short-circuit a `.finished`-boundary
        // page. A page's fields (including a `.finished`-boundary one) were
        // answered by `answer(for:)` during discovery, which falls back to
        // rclone's default whenever `answers` has nothing stored yet — so
        // the remote that currently exists is a defaults-built byproduct,
        // not the user's remote. Under this flow's model a page is an
        // editable form and submitting it applies its answers;
        // `replayAnsweringBoundary`'s delete-and-recreate is not a hazard to
        // route around, it is the ONLY mechanism that applies what the user
        // actually typed.
        //
        // The tradeoff, both halves, so it isn't re-derived a third time:
        //   - Re-walking risks the restart failing partway, landing on
        //     `.failed` with the defaults-built remote deleted and nothing
        //     rebuilt.
        //   - Short-circuiting instead (skip the re-walk, keep whatever
        //     rclone already wrote) risks silently discarding the user's
        //     real edits — they'd press "Add Remote" and get the
        //     placeholder-built remote with no indication anything was
        //     ignored.
        // We chose the loud failure over the silent one: a failed re-walk
        // surfaces as `.failed`, but a silently-kept placeholder gives no
        // signal at all. (This was implemented as a short-circuit once,
        // under the label "S1" in fix round 1's supplement, then withdrawn
        // once this tradeoff was traced through — do not reintroduce it.)
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
        // Uses the askAll captured on .signingIn, not the live `askAll`
        // property — see the case's doc comment (NB-4).
        guard case .signingIn(let question, let signInAskAll) = phase else { return }
        do {
            let next = try await continueWalk(
                state: question.state,
                result: "true", askAll: signInAskAll
            )
            await advance(from: next, askAll: signInAskAll)
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

    /// Questions Nimbus answers on the user's behalf, keyed by option name.
    /// They never reach a page, and the walk's OAuth detection sees the
    /// step after them.
    ///
    /// `config_shared_client_id` (state `client_id_warning`): since rclone
    /// 1.76, Google Drive asks this before `*oauth-islocal` whenever no
    /// client_id was given ("rclone's shared client_id is being retired...
    /// continue using it anyway?", default false). Left as a plain question
    /// it made Drive's first `all:false` step a non-OAuth one, so
    /// `performBegin` threw the walk away and restarted with `all:true`,
    /// asking for client_id/client_secret. "true" keeps Drive a one-click
    /// sign-in like the other OAuth backends and matches what `ReconnectFlow`
    /// answers. "false" would only lead to client_id/client_secret fields,
    /// which "Show all options" already asks for up front — and a client_id
    /// entered there means rclone never asks this question at all.
    private static let automaticAnswers: [String: String] = [
        "config_shared_client_id": "true",
    ]

    /// Answers every leading question in `automaticAnswers` and returns the
    /// first step that isn't one. Every step the walk receives from rclone
    /// passes through here, so an automatic question can never be collected
    /// onto a page or mistaken for the walk's first real step.
    private func skippingAutomaticAnswers(
        _ first: ConfigStep, askAll: Bool
    ) async throws -> ConfigStep {
        var step = first
        var steps = 0
        while case .question(let q) = step,
              let result = Self.automaticAnswers[q.option.name] {
            steps += 1
            guard steps <= maxWalkSteps else { throw StuckWalkError() }
            step = try await client.continueConfig(
                name: name, type: provider.name, state: q.state,
                result: result, askAll: askAll
            )
        }
        return step
    }

    /// Answers one step and returns the next one the walk should look at.
    private func continueWalk(
        state: String, result: String, askAll: Bool
    ) async throws -> ConfigStep {
        let next = try await client.continueConfig(
            name: name, type: provider.name, state: state,
            result: result, askAll: askAll
        )
        return try await skippingAutomaticAnswers(next, askAll: askAll)
    }

    private func start(askAll: Bool) async throws -> ConfigStep {
        // Capture the name this call actually uses, and record it BEFORE
        // calling the client: rclone writes the partial remote on the first
        // config/create call, so a call that throws may still have created
        // the stub. Recording the exact name used means cleanup always
        // targets the remote THIS call touched, even if `name` is edited
        // afterward — deleting a remote that was never created is a
        // harmless no-op, leaking or mistargeting a delete is not.
        let currentName = name
        // Don't record an empty name as the cleanup target — the previous
        // `partialRemoteExists: Bool` shape guarded this with `!name.isEmpty`
        // at cleanup time; restoring the equivalent here (at record time)
        // means `partialRemoteName` can never hold "" and later trigger a
        // `deletePartialRemote(name: "")` call (NB-2).
        if !currentName.isEmpty {
            partialRemoteName = currentName
        }
        let first = try await client.startConfig(
            name: currentName, type: provider.name, askAll: askAll
        )
        return try await skippingAutomaticAnswers(first, askAll: askAll)
    }

    /// Consumes plain questions into a page, stopping at the first boundary.
    /// Does NOT answer the boundary — that is `submitPage`'s job — so simply
    /// rendering a page never creates the remote.
    private func advance(from first: ConfigStep, askAll: Bool) async {
        var collected: [ConfigQuestion] = []
        var step = first
        var steps = 0
        do {
            while true {
                steps += 1
                guard steps <= maxWalkSteps else {
                    await fail(StuckWalkError())
                    return
                }
                switch step {
                case .question(let q):
                    collected.append(q)
                    step = try await continueWalk(
                        state: q.state,
                        result: answer(for: q), askAll: askAll
                    )
                case .oauth(let q):
                    phase = collected.isEmpty
                        ? .signingIn(q, askAll: askAll)
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
                        // complete: clear the cleanup target BEFORE
                        // publishing `.finished`, so a cancel racing the
                        // finish transition can never delete a remote the
                        // user just successfully created.
                        partialRemoteName = nil
                        phase = .finished
                    } else {
                        // This batch's fields were answered via `answer(for:)`,
                        // which falls back to rclone's default whenever
                        // `answers` has nothing stored yet — i.e. the user
                        // hasn't reviewed this page. The remote that exists
                        // right now holds those defaults, not the user's
                        // intent, so leave partialRemoteName set: a cancel
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
    /// only source of truth — including for a `.finished` boundary, where
    /// this replay is what applies the user's real answers over the
    /// defaults the discovery walk used.
    private func replayAnsweringBoundary(askAll: Bool) async throws -> ConfigStep {
        await cleanUpPartialRemote()
        var step = try await start(askAll: askAll)
        var steps = 0
        while case .question(let q) = step {
            steps += 1
            guard steps <= maxWalkSteps else {
                throw StuckWalkError()
            }
            step = try await continueWalk(
                state: q.state,
                result: answer(for: q), askAll: askAll
            )
        }
        switch step {
        case .advancedGate(let q):
            return try await continueWalk(
                state: q.state,
                result: includeAdvanced ? "true" : "false", askAll: askAll
            )
        default:
            // OAuth can't be auto-answered here — it needs a live browser
            // round-trip via signIn() — so hand it back unanswered. `.done`
            // is the only other value the while loop above can exit with
            // (`.question` can't reach here: that's exactly what the loop
            // condition excludes).
            return step
        }
    }

    private func answer(for question: ConfigQuestion) -> String {
        answers[question.option.name] ?? question.option.defaultValue
    }

    private func fail(_ error: Error) async {
        guard !isCancellation(error) else {
            // cancel() aborted the in-flight walk (walkChain?.cancel(), see
            // cancel()'s doc comment) — this is cancel() doing its job, not
            // a failure to surface. Leave `partialRemoteName` set so
            // performCancel's own cleanup, queued right behind this walk on
            // walkChain, can still delete the remote once it gets its turn
            // (NB-1).
            return
        }
        await cleanUpPartialRemote()
        phase = .failed(NimbusError.classify(error).message)
    }

    /// True for a thrown `CancellationError`, a `URLError.cancelled` (how a
    /// cancelled URLSession call — the production client's real transport —
    /// surfaces cancellation), or simply the enclosing Task already being
    /// cancelled regardless of the specific error shape.
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return Task.isCancelled
    }

    private func cleanUpPartialRemote() async {
        guard let partialRemoteName else { return }
        await client.deletePartialRemote(name: partialRemoteName)
        self.partialRemoteName = nil
    }
}
