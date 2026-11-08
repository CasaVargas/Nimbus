# Guided Add Remote

**Date:** 2026-08-30
**Status:** Approved design
**Scope:** Replace the static provider config form in Add Remote with a guided flow driven by rclone's own interactive `config/create` state machine, including OAuth sign-in and a basics-versus-advanced escape hatch.

## Objective

Adding a remote is currently a wall of fields. `AddRemoteSheet` renders every non-advanced option rclone reports for a backend, followed by every advanced option inline in the same scroll — 78 fields for S3, 52 for Google Drive. The existing basic/advanced split in `ConfigForm.swift` does not help, for two reasons measured against rclone 1.74:

1. rclone's "non-advanced" set is not the user's basics. For Drive, Dropbox, OneDrive, Box, and pCloud it is `client_id`, `client_secret`, `scope`, and `service_account_file` — developer plumbing that every ordinary user must leave blank.
2. There is no sign-in anywhere in Nimbus. Adding any OAuth backend through the current sheet writes a remote that cannot authenticate. For the eight services in Nimbus's own "Popular" list, a form is the wrong control entirely.

The redesign has four goals:

1. Ask only the questions that backend actually needs, as rclone defines them.
2. Make OAuth backends a name plus a Sign In button.
3. Give power users every option, without hand-maintaining a per-provider field table.
4. Never leave a partial or unauthenticated remote behind.

## Non-Goals

- Redesigning `EditRemoteSheet`. The state machine is create-only; editing is `config/update`, a different mechanism. `ConfigPageForm` is built so Edit can adopt it later, but that is separate work.
- Hand-curating a "basics" field list per provider. Findings below make this unnecessary.
- Changing `ProviderPicker`. Provider selection, search, and the Popular list stay as they are.
- Reimplementing OAuth. rclone owns the browser handoff and callback.
- Importing or migrating existing remotes. `ImportConfigSheet` is untouched.

## Background: measured rclone behavior

Every fact below was verified against rclone 1.74 on 2026-08-30 and is recorded in Tolaria as `nimbus-rclone-config-state-machine`. The design depends on all of them.

**The state machine exists and is reachable.** `config/create` returns `{Error, Option, Result, State}`. `Option` is the question to render, `State` an opaque cursor. Continuation is `config/create` again — there is no `config/continue` method — with `opt: {continue: true, state:…, result:…}`. Empty `State` and null `Option` mean done.

**`all:true` is already curated.** rclone gates each option by its `Provider` field, skipping inapplicable ones, and ends every walk with a built-in `config_fs_advanced` question. Walk lengths are therefore far shorter than the option counts suggest:

| backend | total options | `all:true` steps |
|---|---|---|
| s3 (provider=AWS) | 78 | 13 |
| drive | 52 | 9 (8 before rclone 1.76; the extra step is `config_shared_client_id`) |
| sftp | 45 | 14 |

`config_fs_advanced` is rclone's own basic/advanced gate. Nimbus surfaces it rather than inventing one.

**`all:false` is safe only for OAuth backends.** For drive, dropbox, onedrive, box, and pcloud the first state is `*oauth-islocal,,,`, which is exactly the desired sign-in-only path. For s3, sftp, b2, and webdav it asks nothing at all and writes a stub `[name]\ntype = sftp` carrying no host and no credentials — a silently broken remote.

**rclone 1.76: Drive asks one question before OAuth.** With no client_id, Drive's first `all:false` state is `client_id_warning` (`config_shared_client_id`: rclone's shared client_id is being retired, continue using it? default false), then `*oauth-islocal`. Nimbus answers it "true" on the user's behalf, wherever it appears in a walk, before deciding whether the backend is OAuth, so Drive stays a one-click sign-in. "false" only leads to client_id/client_secret fields, which "Show all options" already asks for up front, and a client_id entered there means rclone never asks. The re-sign-in flow gives the same answer. Verified against rclone 1.76.0 on 2026-11-08.

**The first call persists a partial remote.** `config/create` writes `[name]\ntype = <backend>` before any question is answered.

**Failures arrive inside HTTP 200.** Config errors populate the response body's `Error` field, not the status code.

## Architecture

Three layers, each testable without the one above it.

```
AddRemoteSheet  ──▶  RemoteSetupFlow  ──▶  ConfigSession  ──▶  rclone RC
   (SwiftUI)         @Observable          (RcloneKit)        config/create
 renders one page   owns the walk,        typed state         config/delete
 of questions       batching, cancel      machine wrapper     config/listremotes
```

### ConfigSession (RcloneKit)

New file `RcloneKit/Sources/RcloneKit/ConfigSession.swift`. Wraps the state machine and returns a typed step rather than raw JSON, so the view layer never parses a state string:

```swift
public enum ConfigStep: Sendable {
    case question(ConfigQuestion)      // a plain option to render
    case oauth(ConfigQuestion)         // *oauth-* state → Sign In
    case advancedGate(ConfigQuestion)  // config_fs_advanced → the toggle
    case done
}

public struct ConfigQuestion: Sendable {
    public let option: ProviderOption
    public let state: String
}
```

Step classification is by state prefix: `*oauth` → `.oauth`; option name `config_fs_advanced` → `.advancedGate`; empty state and no option → `.done`; otherwise `.question`.

Methods, all of which check the body's `Error` field before returning:

```swift
func startConfig(name: String, type: String, askAll: Bool) async throws -> ConfigStep
func continueConfig(name: String, type: String, state: String,
                    result: String, askAll: Bool) async throws -> ConfigStep
```

`Models.swift` gains the fields rclone already sends and `ProviderOption` currently discards: `Sensitive`, `Hide`, `Exclusive`, `DefaultStr`. `Sensitive` drives `SecureField` — today only `IsPassword` does, so SFTP key passphrases render in the clear. `Hide` suppresses options rclone marks internal. `Exclusive` marks branching answers and drives the re-walk below.

Config calls use a dedicated `URLSession` with `timeoutIntervalForResource` raised to 900. `RcloneClient.swift:12` sets it to 300 on the shared session, which would cap a blocking OAuth call at five minutes regardless of the 600-second per-request value, because the resource timeout is the hard ceiling for the whole transfer.

### RemoteSetupFlow (ViewModels)

New `Nimbus/Nimbus/ViewModels/RemoteSetupFlow.swift`, `@Observable @MainActor`, owning all walk state:

```swift
@Observable @MainActor final class RemoteSetupFlow {
    enum Phase { case naming, loading, page(ConfigPage), signingIn, creating, finished }
    var phase: Phase
    var showAllOptions: Bool     // all:false ⇄ all:true
    var includeAdvanced: Bool    // config_fs_advanced answer
    var answers: [String: String]
}
```

`ConfigPage` is a run of consecutive `.question` steps plus the boundary step that terminated it.

Provider selection happens before the flow exists. `AddRemoteSheet` shows `ProviderPicker` first, exactly as today, and constructs `RemoteSetupFlow(provider:client:)` once a provider is chosen. `.naming` is therefore the flow's first phase, not the sheet's first screen, and the sheet's Back action from `.naming` discards the flow and returns to the picker.

## Strategy selection

Basic mode cannot use one flag globally. The flow chooses per backend at runtime, with no hardcoded provider table, by peeking at the first `all:false` state:

| first `all:false` state | backend kind | basic mode uses |
|---|---|---|
| begins with `*oauth` | drive, dropbox, onedrive, box, pcloud | `all:false` — name plus Sign In only |
| empty | s3, sftp, b2, webdav | `all:true`, auto-answering `config_fs_advanced = false` |

The peek is one RC call. Its partial remote is deleted immediately if the flow then restarts with a different `askAll` value.

"Show all options" forces `all:true` for both kinds. Ticking "Edit advanced config" answers `config_fs_advanced = true` and continues into the long tail. Three tiers, one machine, nothing to maintain against rclone releases.

## Page batching

`probe()` walks ahead with each option's default answer, accumulating `.question` steps into one `ConfigPage`, stopping at `.oauth`, `.advancedGate`, or `.done`. That page renders as an ordinary scrollable form. On submit, `commit(page:)` replays the user's real answers through the machine to reach the same boundary.

S3 therefore presents as roughly two pages rather than thirteen sequential prompts, and Drive as a single page plus a sign-in step.

Because a probe walks with defaults, an answer that branches the question set invalidates the page. Re-walk fires when a submitted answer belongs to an option with `Exclusive: true` — S3's `provider` and `env_auth` are the practical cases. Previously supplied answers are preserved by option name and re-applied during the re-walk; questions that no longer appear are dropped from `answers`. The cost is a few loopback HTTP calls to a local daemon.

Probing mutates the partial remote in `rclone.conf`. That is acceptable because the remote is deleted on any exit that is not a successful create.

## View structure

- `AddRemoteSheet.swift` — rewritten to host `RemoteSetupFlow` and switch on `phase`. Keeps `SheetChrome`, the existing provider identity header, and the 560×560 frame. `ProviderPicker` is presented unchanged for the `naming` phase.
- `ConfigPageForm.swift` — new. Renders a `ConfigPage` using the existing `FormSection` and `FormRow` components. Field selection: `SecureField` when `isPassword || sensitive`; `Picker` when `examples` is non-empty, adding a free-text row when `Exclusive` is false; `Toggle` for `type == "bool"`; `TextField` otherwise. Options with `Hide != 0` are skipped.
- `OAuthStep.swift` — new. Renders the provider badge, an explanatory line ("Opens your browser. Nimbus never sees your password."), a prominent Sign In button, and a "Waiting for your browser…" progress state with a working Cancel.
- `ConfigForm.swift` — deleted. Its identity-header block moves into `AddRemoteSheet`.

Both call sites, `RemotesSidebarSection.swift:73` and `OnboardingView.swift:40`, keep their current `AddRemoteSheet(client:onDismiss:)` signature.

## State ownership

`RemoteSetupFlow` owns the walk; `ConfigSession` is stateless between calls; the authoritative partial config lives in `rclone.conf` and is owned by the daemon. The flow holds no credentials beyond the in-flight `answers` dictionary, which is discarded when the sheet closes.

The remote name is asked by Nimbus before the walk begins, not by rclone. `config/create` keys on the name from the first call and it cannot be changed later in the flow. The name is validated against `config/listremotes` for collisions before starting.

## Error handling

**Partial remote cleanup is mandatory.** `config/create` persists `[name]\ntype = <backend>` on the first call, so cancelling mid-flow would litter `rclone.conf` with unusable remotes. `RemoteSetupFlow.cancel()`, every thrown error path, and sheet dismissal must `config/delete` the partial remote. This includes the strategy-selection peek and every re-walk.

**Errors inside 200 responses.** `ConfigSession` checks the body's `Error` field on every call and throws before classification, routing through the existing `NimbusError.classify`.

**OAuth.** The RC call blocks while rclone binds `127.0.0.1:53682` and opens the browser. Nimbus is not sandboxed — `Nimbus.entitlements` has `app-sandbox = false` — so this works without a token-scraping workaround. The UI shows a waiting state with Cancel; cancelling deletes the partial remote. A failed or abandoned sign-in returns an rclone error, surfaced in place with the Sign In button restored rather than dismissing the sheet.

**Daemon restart mid-flow.** The `State` cursor is meaningless to a daemon whose `rclone.conf` no longer holds the partial remote. If a continuation fails with a missing-type error, the flow deletes any stub, returns to the first page, and preserves `answers` for replay.

## Accessibility and localization

`option.name` and `option.help` are runtime English strings from rclone and cannot be localized; they continue to be rendered with `Text(verbatim:)` and `LocalizedStringKey` construction exactly as `ConfigForm` does today, with the same caveat. Nimbus's own chrome — phase titles, Sign In, Cancel, the two toggles, waiting states — is localized. Each question row carries an accessibility label from the option name and a hint from its help text. The sign-in waiting state posts an accessibility announcement when it begins and ends.

## Verification

**Unit tests**, on captured rclone 1.74 JSON fixtures for drive, dropbox, s3, and sftp, in `NimbusTests`:

- `ConfigStep` classification for `*oauth-islocal`, `*all-set`, `config_fs_advanced`, and terminal states.
- `ProviderOption` decoding of `Sensitive`, `Hide`, `Exclusive`, `DefaultStr`, including the existing polymorphic `Default`/`Value` handling.
- Page batching stops at each boundary step type.
- Re-walk triggers on an `Exclusive` answer and preserves unrelated answers.
- Cancel issues `config/delete` for the partial remote; assert on the captured request.
- A non-200 `Error` body throws rather than reporting success.

**Integration test**, skipped when rclone is absent from PATH: port the walk harness recorded in the Tolaria note, asserting s3 = 13, drive = 8, sftp = 14 steps, and that `all:false` on sftp asks nothing. This is the canary for rclone upgrades changing the flow.

**Visual verification** via `RenderPreview` on three page shapes: OAuth basic (Drive), credential basic (SFTP), and show-all (S3 with `provider = AWS`). Per CLAUDE.md, UI changes are confirmed visually before the work is called done.

**Manual**, against a real account: add a Drive remote end to end through browser sign-in, confirm it browses; add an S3 remote with a custom endpoint via Show All Options; cancel each flow at every phase and confirm `rclone.conf` contains no leftover stub.

## Delivery Boundary

Done means: `ConfigSession` and the `ProviderOption` field additions land in RcloneKit with unit tests; `RemoteSetupFlow` drives the walk with batching, re-walk, and guaranteed cleanup; `AddRemoteSheet` renders the guided flow with both toggles; OAuth sign-in completes for at least one real provider; `ConfigForm.swift` is deleted; both call sites build unchanged; the integration canary passes; and the three `RenderPreview` shapes are visually confirmed.

`EditRemoteSheet` still uses its current form. Adopting `ConfigPageForm` there is follow-on work.
