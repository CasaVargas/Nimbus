# Guided Add Remote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Nimbus's static provider config form with a guided Add Remote flow driven by rclone's own `config/create` state machine, giving OAuth backends a Sign In button and everything else a short, curated form with an ask-everything toggle.

**Architecture:** Three layers. `ConfigSession` (RcloneKit) wraps rclone's interactive `config/create` state machine and returns typed steps. `RemoteSetupFlow` (`@Observable @MainActor` view model) replays an answers dictionary through that machine to produce one form page at a time, and guarantees the partial remote rclone writes on the first call is deleted on every abort path. `AddRemoteSheet` renders whichever page the flow is on.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, macOS 15.0 target, Swift Testing (`import Testing`, `@Test`, `#expect`), XcodeGen, rclone 1.74 RC API.

**Spec:** `docs/superpowers/specs/2026-08-30-guided-add-remote-design.md`

## Global Constraints

- Swift 6.0, `SWIFT_STRICT_CONCURRENCY: complete`. All new types crossing concurrency domains must be `Sendable`.
- macOS deployment target 15.0.
- Tests use **Swift Testing**, not XCTest. `import Testing`, `@Test func name()`, `#expect(...)`.
- View models are `@Observable @MainActor`. Services are actors or `@unchecked Sendable` where justified.
- `Provider` and `ProviderOption` are **decode-only** — they have no public memberwise init. Test fixtures must be built by decoding JSON, following the pattern in `Nimbus/NimbusTests/ProviderPickerTests.swift:12-15`.
- `option.name` and `option.help` are runtime English strings from rclone. Render with `LocalizedStringKey(option.name)` / `Text(verbatim:)` exactly as the current code does. Do not attempt to localize them.
- No `.system(size:)` anywhere — a pre-build lint script (`scripts/lint-no-system-size.sh`) fails the build. Use `DesignSystem.Typography` tokens.
- After adding or removing any file under `Nimbus/`, run `cd Nimbus && xcodegen generate`.
- Build command: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build`
- RcloneKit tests: `swift test --package-path RcloneKit`
- Conventional commit messages, small and focused.

---

## File Structure

**RcloneKit (Swift package):**

| File | Responsibility |
|---|---|
| `RcloneKit/Sources/RcloneKit/ConfigSession.swift` | **Create.** Typed wrapper over the `config/create` state machine: `ConfigStep`, `ConfigQuestion`, `startConfig`, `continueConfig`, `deletePartialRemote`. |
| `RcloneKit/Sources/RcloneKit/Models.swift` | **Modify.** Add `sensitive`, `hide`, `exclusive`, `defaultStr` to `ProviderOption`; make it and `ProviderExample` `Equatable`. |
| `RcloneKit/Sources/RcloneKit/RcloneClient.swift` | **Modify.** Add a long-lived `configSession` URLSession whose `timeoutIntervalForResource` accommodates a blocking OAuth call. |
| `RcloneKit/Tests/RcloneKitTests/RcloneClientTests.swift` | **Modify.** Extend `MockURLProtocol` with response *queues* and request-body capture. |
| `RcloneKit/Tests/RcloneKitTests/ConfigSessionTests.swift` | **Create.** Step classification, error-in-200, continuation payload shape. |

**Nimbus app:**

| File | Responsibility |
|---|---|
| `Nimbus/Nimbus/ViewModels/RemoteSetupFlow.swift` | **Create.** Owns the walk, answers, page batching, strategy selection, cleanup. |
| `Nimbus/Nimbus/Views/Remotes/ConfigFieldView.swift` | **Create.** One option → one input control. Shared by the new form and `EditRemoteSheet`. |
| `Nimbus/Nimbus/Views/Remotes/ConfigPageForm.swift` | **Create.** Renders a `ConfigPage` as `FormSection`/`FormRow` rows. |
| `Nimbus/Nimbus/Views/Remotes/OAuthStep.swift` | **Create.** Sign In button, waiting state, cancel. |
| `Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift` | **Rewrite.** Hosts `RemoteSetupFlow`, switches on phase. |
| `Nimbus/Nimbus/Views/Remotes/ConfigForm.swift` | **Delete.** Superseded. Only referenced from comments elsewhere. |
| `Nimbus/Nimbus/Views/Remotes/EditRemoteSheet.swift` | **Modify.** Replace its duplicated `field(for:)` with `ConfigFieldView` — this is how the `Sensitive` fix reaches Edit too. |
| `Nimbus/NimbusTests/RemoteSetupFlowTests.swift` | **Create.** Batching, strategy selection, re-walk, cleanup. |
| `Nimbus/NimbusTests/GuidedAddRemoteSnapshotTests.swift` | **Create.** Three page shapes. |
| `Nimbus/NimbusTests/RcloneConfigMachineTests.swift` | **Create.** Integration canary against real rclone. |

**Why `ConfigFieldView` is split out:** `EditRemoteSheet.swift:123-148` currently duplicates `ConfigForm`'s field-rendering logic verbatim. Both need the `Sensitive` fix. Extracting one view fixes both and removes the duplication rather than adding a third copy.

---

### Task 1: Mock harness — response queues and body capture

`MockURLProtocol` stores exactly one canned response per endpoint path. Every `ConfigSession` test needs a *sequence* of different responses from `config/create`, and several need to assert on the request body. Both are prerequisites for all later tasks.

**Files:**
- Modify: `RcloneKit/Tests/RcloneKitTests/RcloneClientTests.swift:5-40` (the `MockURLProtocol` class)

**Interfaces:**
- Consumes: nothing.
- Produces: `MockURLProtocol.enqueue(endpoint:json:status:)`, `MockURLProtocol.resetQueues()`, `MockURLProtocol.lastRequestBodies: [String: Data]`, and the existing `makeTestClient() -> RcloneClient`.

- [ ] **Step 1: Write the failing test**

Add to `RcloneKit/Tests/RcloneKitTests/RcloneClientTests.swift`:

```swift
@Test func mockQueueReturnsResponsesInOrder() async throws {
    MockURLProtocol.resetQueues()
    MockURLProtocol.enqueue(endpoint: "rc/noop", json: #"{"n": 1}"#)
    MockURLProtocol.enqueue(endpoint: "rc/noop", json: #"{"n": 2}"#)

    struct Counted: Decodable, Sendable { let n: Int }
    let client = makeTestClient()

    let first: Counted = try await client.call("rc/noop")
    let second: Counted = try await client.call("rc/noop")
    #expect(first.n == 1)
    #expect(second.n == 2)

    // Queue exhausted → falls back to the static registration.
    let third: [String: String] = try await client.call("rc/noop")
    #expect(third.isEmpty)
}

@Test func mockCapturesRequestBody() async throws {
    MockURLProtocol.resetQueues()
    let client = makeTestClient()
    try await client.createRemote(name: "bodytest", type: "s3", parameters: ["region": "us-east-1"])

    let body = try #require(MockURLProtocol.lastRequestBodies["config/create"])
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["name"] as? String == "bodytest")
    #expect(json["type"] as? String == "s3")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path RcloneKit --filter mockQueue`
Expected: FAIL — `type 'MockURLProtocol' has no member 'resetQueues'`.

- [ ] **Step 3: Implement**

In `RcloneClientTests.swift`, add to `MockURLProtocol` alongside the existing statics:

```swift
    /// FIFO queues per endpoint, checked before `mockResponses`. Lets one
    /// test script a *sequence* of replies from a single endpoint — required
    /// for config/create, which returns a different question each call.
    nonisolated(unsafe) static var responseQueues: [String: [(Data, Int)]] = [:]

    /// Last request body seen per endpoint path. URLProtocol nils out
    /// `request.httpBody` for POSTs, so this is read from `httpBodyStream`.
    nonisolated(unsafe) static var lastRequestBodies: [String: Data] = [:]

    static func enqueue(endpoint: String, json: String, status: Int = 200) {
        responseQueues[endpoint, default: []].append((json.data(using: .utf8)!, status))
    }

    static func resetQueues() {
        responseQueues.removeAll()
        lastRequestBodies.removeAll()
    }

    /// URLProtocol hands POST bodies over as a stream, not `httpBody`.
    private static func readBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
```

Then replace the body of `startLoading()` after the `lastRequestURLs` assignment:

```swift
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        Self.lastRequestURLs[path] = url
        if let body = Self.readBody(request) { Self.lastRequestBodies[path] = body }

        let queued: (Data, Int)? = {
            guard var queue = Self.responseQueues[path], !queue.isEmpty else { return nil }
            let head = queue.removeFirst()
            Self.responseQueues[path] = queue
            return head
        }()

        if let (data, status) = queued ?? Self.mockResponses[path] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
        }
        client?.urlProtocolDidFinishLoading(self)
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path RcloneKit`
Expected: PASS, all existing tests still green.

Note: existing suites are not `.serialized` and mutate shared statics. If the two new tests flake when run alongside others, mark them `@Test(.serialized)`.

- [ ] **Step 5: Commit**

```bash
git add RcloneKit/Tests/RcloneKitTests/RcloneClientTests.swift
git commit -m "test(rclonekit): add mock response queues and body capture"
```

---

### Task 2: ProviderOption gains the fields rclone already sends

rclone's option JSON carries `Sensitive`, `Hide`, `Exclusive`, and `DefaultStr`; `ProviderOption` discards all four. `Sensitive` is the one with a live consequence — SFTP key passphrases currently render in a plain `TextField`.

**Files:**
- Modify: `RcloneKit/Sources/RcloneKit/Models.swift:140-205`
- Test: `RcloneKit/Tests/RcloneKitTests/ModelsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ProviderOption.sensitive: Bool`, `.hide: Int`, `.exclusive: Bool`, `.defaultStr: String`; `ProviderOption: Equatable`, `ProviderExample: Equatable`.

- [ ] **Step 1: Write the failing test**

Add to `RcloneKit/Tests/RcloneKitTests/ModelsTests.swift`:

```swift
@Test func providerOptionDecodesSensitivityAndBranchingFields() throws {
    let json = #"""
    {
        "Name": "secret_access_key", "Help": "AWS Secret Access Key.",
        "Type": "string", "Required": false, "IsPassword": false,
        "Advanced": false, "Sensitive": true, "Hide": 0,
        "Exclusive": false, "Default": "", "DefaultStr": "", "Value": null
    }
    """#
    let option = try JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
    #expect(option.sensitive == true)
    #expect(option.hide == 0)
    #expect(option.exclusive == false)
    #expect(option.isPassword == false)
}

@Test func providerOptionDefaultsMissingNewFields() throws {
    // Older rclone builds and hand-written fixtures omit these keys.
    let json = #"""
    {"Name": "region", "Help": "", "Type": "string", "Required": false,
     "IsPassword": false, "Advanced": false}
    """#
    let option = try JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
    #expect(option.sensitive == false)
    #expect(option.hide == 0)
    #expect(option.exclusive == false)
    #expect(option.defaultStr == "")
}

@Test func providerOptionDecodesExclusiveExampleField() throws {
    let json = #"""
    {"Name": "provider", "Help": "Choose your S3 provider.", "Type": "string",
     "Required": false, "IsPassword": false, "Advanced": false,
     "Exclusive": true, "Sensitive": false, "Hide": 0,
     "Examples": [{"Value": "AWS", "Help": "Amazon Web Services"}]}
    """#
    let option = try JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
    #expect(option.exclusive == true)
    #expect(option.examples?.first?.value == "AWS")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path RcloneKit --filter providerOption`
Expected: FAIL — `value of type 'ProviderOption' has no member 'sensitive'`.

- [ ] **Step 3: Implement**

In `Models.swift`, change the `ProviderOption` declaration line to add `Equatable`:

```swift
public struct ProviderOption: Codable, Sendable, Identifiable, Equatable {
```

Add these stored properties after `public let examples: [ProviderExample]?`:

```swift
    /// rclone marks credential-ish fields `Sensitive` separately from
    /// `IsPassword`. Both must render as SecureField.
    public let sensitive: Bool
    /// Non-zero means rclone considers the option internal; don't render it.
    public let hide: Int
    /// True when the answer branches the remaining question set (s3's
    /// `provider`, `env_auth`). Answering one of these invalidates the
    /// current page and forces a re-walk.
    public let exclusive: Bool
    /// rclone's pre-rendered default string, used as the field placeholder.
    public let defaultStr: String
```

Add the coding keys inside `enum CodingKeys`:

```swift
        case sensitive = "Sensitive"
        case hide = "Hide"
        case exclusive = "Exclusive"
        case defaultStr = "DefaultStr"
```

Add to `init(from decoder:)`, after the `examples` line:

```swift
        sensitive = (try? container.decode(Bool.self, forKey: .sensitive)) ?? false
        hide = (try? container.decode(Int.self, forKey: .hide)) ?? 0
        exclusive = (try? container.decode(Bool.self, forKey: .exclusive)) ?? false
        defaultStr = (try? container.decode(String.self, forKey: .defaultStr)) ?? ""
```

Make `ProviderExample` Equatable:

```swift
public struct ProviderExample: Codable, Sendable, Equatable {
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path RcloneKit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add RcloneKit/Sources/RcloneKit/Models.swift RcloneKit/Tests/RcloneKitTests/ModelsTests.swift
git commit -m "feat(rclonekit): decode Sensitive, Hide, Exclusive, DefaultStr on ProviderOption"
```

---

### Task 3: ConfigSession — typed state machine wrapper

**Files:**
- Create: `RcloneKit/Sources/RcloneKit/ConfigSession.swift`
- Modify: `RcloneKit/Sources/RcloneKit/RcloneClient.swift:7-15`
- Test: `RcloneKit/Tests/RcloneKitTests/ConfigSessionTests.swift`

**Interfaces:**
- Consumes: `ProviderOption` with the Task 2 fields; `MockURLProtocol.enqueue` from Task 1; `RcloneClient.call(_:params:)`.
- Produces:
  - `public enum ConfigStep: Sendable, Equatable { case question(ConfigQuestion), oauth(ConfigQuestion), advancedGate(ConfigQuestion), done }`
  - `public struct ConfigQuestion: Sendable, Equatable { let option: ProviderOption; let state: String }`
  - `RcloneClient.startConfig(name:type:askAll:) async throws -> ConfigStep`
  - `RcloneClient.continueConfig(name:type:state:result:askAll:) async throws -> ConfigStep`
  - `RcloneClient.deletePartialRemote(name:) async` (never throws)

- [ ] **Step 1: Write the failing test**

Create `RcloneKit/Tests/RcloneKitTests/ConfigSessionTests.swift`:

```swift
import Foundation
import Testing
@testable import RcloneKit

private func optionJSON(
    name: String, advanced: Bool = false, exclusive: Bool = false
) -> String {
    #"""
    {"Name": "\#(name)", "Help": "help for \#(name)", "Type": "string",
     "Required": false, "IsPassword": false, "Advanced": \#(advanced),
     "Sensitive": false, "Hide": 0, "Exclusive": \#(exclusive),
     "Default": "", "DefaultStr": "", "Value": null}
    """#
}

private func machineJSON(state: String, option: String?) -> String {
    #"""
    {"Error": "", "Result": "", "State": "\#(state)",
     "Option": \#(option ?? "null")}
    """#
}

@Suite("ConfigSession", .serialized)
struct ConfigSessionTests {

    @Test func plainOptionBecomesQuestion() async throws {
        MockURLProtocol.resetQueues()
        MockURLProtocol.enqueue(
            endpoint: "config/create",
            json: machineJSON(state: "*all-set,0,false", option: optionJSON(name: "host"))
        )
        let step = try await makeTestClient().startConfig(name: "r", type: "sftp", askAll: true)
        guard case .question(let q) = step else {
            Issue.record("expected .question, got \(step)"); return
        }
        #expect(q.option.name == "host")
        #expect(q.state == "*all-set,0,false")
    }

    @Test func oauthStatePrefixBecomesOAuthStep() async throws {
        MockURLProtocol.resetQueues()
        MockURLProtocol.enqueue(
            endpoint: "config/create",
            json: machineJSON(state: "*oauth-islocal,,,", option: optionJSON(name: "config_is_local"))
        )
        let step = try await makeTestClient().startConfig(name: "r", type: "drive", askAll: false)
        guard case .oauth = step else {
            Issue.record("expected .oauth, got \(step)"); return
        }
    }

    @Test func configFsAdvancedBecomesAdvancedGate() async throws {
        MockURLProtocol.resetQueues()
        MockURLProtocol.enqueue(
            endpoint: "config/create",
            json: machineJSON(state: "*all-set,12,false", option: optionJSON(name: "config_fs_advanced"))
        )
        let step = try await makeTestClient().startConfig(name: "r", type: "s3", askAll: true)
        guard case .advancedGate = step else {
            Issue.record("expected .advancedGate, got \(step)"); return
        }
    }

    @Test func emptyStateBecomesDone() async throws {
        MockURLProtocol.resetQueues()
        MockURLProtocol.enqueue(
            endpoint: "config/create",
            json: machineJSON(state: "", option: nil)
        )
        let step = try await makeTestClient().startConfig(name: "r", type: "s3", askAll: false)
        #expect(step == .done)
    }

    @Test func errorInsideTwoHundredThrows() async throws {
        MockURLProtocol.resetQueues()
        MockURLProtocol.enqueue(
            endpoint: "config/create",
            json: #"{"Error": "couldn't fetch token: bad credentials", "Result": "", "State": "", "Option": null}"#
        )
        await #expect(throws: RcloneError.self) {
            _ = try await makeTestClient().startConfig(name: "r", type: "drive", askAll: false)
        }
    }

    @Test func continueSendsStateAndResultInsideOpt() async throws {
        MockURLProtocol.resetQueues()
        MockURLProtocol.enqueue(
            endpoint: "config/create",
            json: machineJSON(state: "", option: nil)
        )
        _ = try await makeTestClient().continueConfig(
            name: "r", type: "sftp", state: "*all-set,0,false",
            result: "example.com", askAll: true
        )
        let body = try #require(MockURLProtocol.lastRequestBodies["config/create"])
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let opt = try #require(json["opt"] as? [String: Any])
        #expect(opt["continue"] as? Bool == true)
        #expect(opt["state"] as? String == "*all-set,0,false")
        #expect(opt["result"] as? String == "example.com")
        #expect(opt["all"] as? Bool == true)
        #expect(opt["nonInteractive"] as? Bool == true)
        #expect(json["name"] as? String == "r")
        #expect(json["type"] as? String == "sftp")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path RcloneKit --filter ConfigSession`
Expected: FAIL — `cannot find 'ConfigStep' in scope`.

- [ ] **Step 3: Implement**

Create `RcloneKit/Sources/RcloneKit/ConfigSession.swift`:

```swift
import Foundation

/// One question rclone's interactive config machine is asking, plus the
/// opaque cursor to echo back when answering it.
public struct ConfigQuestion: Sendable, Equatable {
    public let option: ProviderOption
    public let state: String

    public init(option: ProviderOption, state: String) {
        self.option = option
        self.state = state
    }
}

/// A typed view of one turn of rclone's `config/create` state machine, so
/// callers never parse a state string themselves.
public enum ConfigStep: Sendable, Equatable {
    /// A plain option to render as a form field.
    case question(ConfigQuestion)
    /// An `*oauth-*` state: browser sign-in, not a text field.
    case oauth(ConfigQuestion)
    /// rclone's own `config_fs_advanced` gate — "edit advanced config?"
    case advancedGate(ConfigQuestion)
    /// Machine finished; the remote now exists in rclone.conf.
    case done
}

/// Raw shape of a `config/create` reply. `Result` is deliberately not
/// decoded — nothing in Nimbus reads it.
private struct ConfigMachineResponse: Decodable, Sendable {
    let error: String
    let option: ProviderOption?
    let state: String

    enum CodingKeys: String, CodingKey {
        case error = "Error"
        case option = "Option"
        case state = "State"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = (try? c.decode(String.self, forKey: .error)) ?? ""
        option = try? c.decodeIfPresent(ProviderOption.self, forKey: .option)
        state = (try? c.decode(String.self, forKey: .state)) ?? ""
    }
}

extension RcloneClient {

    /// Begins an interactive config walk.
    ///
    /// `askAll: false` asks only rclone's post-config questions. That is
    /// correct for OAuth backends (drive, dropbox, onedrive, box, pcloud),
    /// which jump straight to `*oauth-islocal`. It is WRONG for credential
    /// backends (s3, sftp, b2, webdav): they ask nothing at all and rclone
    /// writes a stub remote with no host and no credentials. Callers detect
    /// the difference by whether this returns `.oauth`.
    public func startConfig(
        name: String,
        type: String,
        askAll: Bool
    ) async throws -> ConfigStep {
        try await configCall(name: name, type: type, opt: [
            "nonInteractive": true,
            "all": askAll,
        ])
    }

    /// Answers the current question and returns the next step.
    ///
    /// Note there is no `config/continue` RC method — continuation is
    /// `config/create` again with the cursor carried inside `opt`.
    public func continueConfig(
        name: String,
        type: String,
        state: String,
        result: String,
        askAll: Bool
    ) async throws -> ConfigStep {
        try await configCall(name: name, type: type, opt: [
            "nonInteractive": true,
            "all": askAll,
            "continue": true,
            "state": state,
            "result": result,
        ])
    }

    /// Removes the partial remote `config/create` writes on its first call.
    /// Deliberately swallows errors: it runs on cancel and error paths where
    /// the remote may legitimately not exist yet.
    public func deletePartialRemote(name: String) async {
        try? await deleteRemote(name: name)
    }

    private func configCall(
        name: String,
        type: String,
        opt: [String: any Sendable]
    ) async throws -> ConfigStep {
        let response: ConfigMachineResponse = try await call("config/create", params: [
            "name": name,
            "type": type,
            "parameters": [String: String](),
            "opt": opt,
        ])

        // rclone reports config failures in the body of a 200, not the
        // status code. Checking only the status reports success on failure.
        guard response.error.isEmpty else {
            throw RcloneError.requestFailed(status: 200, message: response.error)
        }

        guard let option = response.option, !response.state.isEmpty else {
            return .done
        }
        let question = ConfigQuestion(option: option, state: response.state)
        if response.state.hasPrefix("*oauth") { return .oauth(question) }
        if option.name == "config_fs_advanced" { return .advancedGate(question) }
        return .question(question)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path RcloneKit`
Expected: PASS, 6 new tests green.

- [ ] **Step 5: Raise the resource timeout for config calls**

`RcloneClient.swift:12` sets `timeoutIntervalForResource = 300`, the hard ceiling for a whole transfer. An OAuth `config/create` blocks while rclone waits for the browser callback, so five minutes is too tight and the per-request 600s does not override it.

In `RcloneClient.swift`, change the default session config:

```swift
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            // 900, not 300: an OAuth config/create blocks while rclone waits
            // on the browser callback, and timeoutIntervalForResource is the
            // hard ceiling for the whole transfer regardless of any
            // per-request timeoutInterval.
            config.timeoutIntervalForResource = 900
            return URLSession(configuration: config)
```

- [ ] **Step 6: Run the full package suite**

Run: `swift test --package-path RcloneKit`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add RcloneKit/Sources/RcloneKit/ConfigSession.swift \
        RcloneKit/Sources/RcloneKit/RcloneClient.swift \
        RcloneKit/Tests/RcloneKitTests/ConfigSessionTests.swift
git commit -m "feat(rclonekit): add typed ConfigSession over rclone's config state machine"
```

---

### Task 4: RemoteSetupFlow — the walk, batching, and cleanup

The core view model. Every walk **restarts from `startConfig` and replays the answers dictionary**, which makes the walk idempotent and turns re-walking into an ordinary call rather than a special case.

**Files:**
- Create: `Nimbus/Nimbus/ViewModels/RemoteSetupFlow.swift`
- Test: `Nimbus/NimbusTests/RemoteSetupFlowTests.swift`

**Interfaces:**
- Consumes: `ConfigStep`, `ConfigQuestion`, `startConfig`, `continueConfig`, `deletePartialRemote` from Task 3.
- Produces:
  - `struct ConfigPage: Equatable { let questions: [ConfigQuestion]; let boundary: Boundary }`
  - `enum ConfigPage.Boundary: Equatable { case oauth(ConfigQuestion), advancedGate(ConfigQuestion), finished }`
  - `@Observable @MainActor final class RemoteSetupFlow` with `phase`, `name`, `answers`, `showAllOptions`, `includeAdvanced`, `begin()`, `submitPage()`, `signIn()`, `cancel()`.
  - `enum RemoteSetupFlow.Phase: Equatable { case naming, loading, page(ConfigPage), signingIn, creating, finished, failed(String) }`

- [ ] **Step 1: Write the failing test**

Create `Nimbus/NimbusTests/RemoteSetupFlowTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test -only-testing:NimbusTests/RemoteSetupFlow`
Expected: FAIL to compile — `cannot find 'RemoteSetupFlow' in scope`.

- [ ] **Step 3: Implement**

Create `Nimbus/Nimbus/ViewModels/RemoteSetupFlow.swift`:

```swift
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
        if let injectedFailure { throw injectedFailure }
        partialRemoteExists = true
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Nimbus && xcodegen generate && cd .. && xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test -only-testing:NimbusTests/RemoteSetupFlow`
Expected: PASS, 6 tests green.

- [ ] **Step 5: Commit**

```bash
git add Nimbus/Nimbus/ViewModels/RemoteSetupFlow.swift Nimbus/NimbusTests/RemoteSetupFlowTests.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(remotes): add RemoteSetupFlow driving rclone's config machine"
```

---

### Task 5: Re-walk on branching answers

An answer to an `Exclusive` option (s3's `provider`, `env_auth`) changes which questions follow, so the rendered page is stale the moment it changes. Answers already given are kept by option name; questions that disappear are dropped.

**Files:**
- Modify: `Nimbus/Nimbus/ViewModels/RemoteSetupFlow.swift`
- Test: `Nimbus/NimbusTests/RemoteSetupFlowTests.swift`

**Interfaces:**
- Consumes: `RemoteSetupFlow` from Task 4; `ProviderOption.exclusive` from Task 2.
- Produces: `RemoteSetupFlow.answerChanged(_ question: ConfigQuestion, to value: String) async`.

- [ ] **Step 1: Write the failing test**

Append to `RemoteSetupFlowTests.swift` inside the suite:

```swift
    @Test func exclusiveAnswerTriggersRewalk() async throws {
        let client = ScriptedConfigClient()
        client.script = [
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
        client.script = [
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
        client.script = [
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test -only-testing:NimbusTests/RemoteSetupFlow`
Expected: FAIL — `value of type 'RemoteSetupFlow' has no member 'answerChanged'`.

- [ ] **Step 3: Implement**

Add to `RemoteSetupFlow`, after `submitPage()`:

```swift
    /// Records an answer. Answers to `Exclusive` options branch the remaining
    /// question set, so the current page is stale and the walk restarts;
    /// everything else just updates the dictionary in place.
    func answerChanged(_ question: ConfigQuestion, to value: String) async {
        answers[question.option.name] = value
        guard question.option.exclusive else { return }
        await rewalk()
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test -only-testing:NimbusTests/RemoteSetupFlow`
Expected: PASS, 9 tests green.

- [ ] **Step 5: Commit**

```bash
git add Nimbus/Nimbus/ViewModels/RemoteSetupFlow.swift Nimbus/NimbusTests/RemoteSetupFlowTests.swift
git commit -m "feat(remotes): re-walk config machine when a branching answer changes"
```

---

### Task 6: ConfigFieldView — one shared option renderer

`ConfigForm.swift:78-104` and `EditRemoteSheet.swift:123-148` contain the same `field(for:)` logic twice. Both need the `Sensitive` fix. Extract one view, use it in Edit now, and the new form gets it in Task 7.

**Files:**
- Create: `Nimbus/Nimbus/Views/Remotes/ConfigFieldView.swift`
- Modify: `Nimbus/Nimbus/Views/Remotes/EditRemoteSheet.swift:123-148`
- Test: `Nimbus/NimbusTests/ConfigFieldViewTests.swift`

**Interfaces:**
- Consumes: `ProviderOption.sensitive`, `.hide`, `.exclusive`, `.defaultStr` from Task 2.
- Produces: `ConfigFieldView(option: ProviderOption, value: Binding<String>)`, and `ConfigFieldView.isSecure(_:) -> Bool` / `ConfigFieldView.shouldRender(_:) -> Bool` as testable statics.

- [ ] **Step 1: Write the failing test**

Create `Nimbus/NimbusTests/ConfigFieldViewTests.swift`:

```swift
import Testing
import Foundation
import RcloneKit
@testable import Nimbus

private func option(
    _ name: String, type: String = "string", isPassword: Bool = false,
    sensitive: Bool = false, hide: Int = 0
) -> ProviderOption {
    let json = #"""
    {"Name": "\#(name)", "Help": "", "Type": "\#(type)", "Required": false,
     "IsPassword": \#(isPassword), "Advanced": false, "Sensitive": \#(sensitive),
     "Hide": \#(hide), "Exclusive": false, "Default": "", "DefaultStr": "", "Value": null}
    """#
    return try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
}

@Suite("ConfigFieldView")
struct ConfigFieldViewTests {

    @Test func passwordOptionsAreSecure() {
        #expect(ConfigFieldView.isSecure(option("pass", isPassword: true)))
    }

    @Test func sensitiveOptionsAreAlsoSecure() {
        // SFTP's key_file_pass is Sensitive but not IsPassword — it rendered
        // in the clear before this.
        #expect(ConfigFieldView.isSecure(option("key_file_pass", sensitive: true)))
    }

    @Test func ordinaryOptionsAreNotSecure() {
        #expect(!ConfigFieldView.isSecure(option("host")))
    }

    @Test func hiddenOptionsAreNotRendered() {
        #expect(!ConfigFieldView.shouldRender(option("internal_thing", hide: 1)))
        #expect(ConfigFieldView.shouldRender(option("host")))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Nimbus && xcodegen generate && cd .. && xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test -only-testing:NimbusTests/ConfigFieldView`
Expected: FAIL — `cannot find 'ConfigFieldView' in scope`.

- [ ] **Step 3: Implement**

Create `Nimbus/Nimbus/Views/Remotes/ConfigFieldView.swift`:

```swift
import SwiftUI
import RcloneKit

/// Renders one rclone provider option as its appropriate input control.
///
/// Shared by `ConfigPageForm` (Add) and `EditRemoteSheet` (Edit) — the two
/// carried duplicate copies of this logic, and both needed the `Sensitive`
/// fix, so there is one copy now.
struct ConfigFieldView: View {
    let option: ProviderOption
    @Binding var value: String

    /// rclone flags credentials two different ways: `IsPassword` for things
    /// it obscures in the config file, `Sensitive` for things that merely
    /// shouldn't be shoulder-surfed (SFTP key passphrases, API secrets).
    /// Both deserve a SecureField.
    static func isSecure(_ option: ProviderOption) -> Bool {
        option.isPassword || option.sensitive
    }

    /// Non-zero `Hide` means rclone considers the option internal.
    static func shouldRender(_ option: ProviderOption) -> Bool {
        option.hide == 0
    }

    private var placeholder: String {
        option.defaultStr.isEmpty ? option.defaultValue : option.defaultStr
    }

    var body: some View {
        if Self.isSecure(option) {
            SecureField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
        } else if let examples = option.examples, !examples.isEmpty {
            Picker("", selection: $value) {
                Text("Choose…").tag("")
                ForEach(examples, id: \.value) { example in
                    Text(verbatim: example.value).tag(example.value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
        } else if option.type == "bool" {
            Toggle("", isOn: Binding(
                get: { value.lowercased() == "true" },
                set: { value = $0 ? "true" : "false" }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        } else {
            TextField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
        }
    }
}
```

- [ ] **Step 4: Adopt it in EditRemoteSheet**

In `EditRemoteSheet.swift`, delete the whole `@ViewBuilder private func field(for option:)` method (lines 123-148) and change `formRow(for:)` to:

```swift
    private func formRow(for option: ProviderOption) -> some View {
        FormRow(
            label: LocalizedStringKey(option.name),
            help: option.help.isEmpty ? nil : LocalizedStringKey(option.help)
        ) {
            ConfigFieldView(option: option, value: binding(for: option.name))
        }
    }
```

Also filter hidden options where `nonAdvanced` and `advanced` are computed — add `.filter(ConfigFieldView.shouldRender)` to both.

- [ ] **Step 5: Run to verify it passes**

Run: `cd Nimbus && xcodegen generate && cd .. && xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test -only-testing:NimbusTests`
Expected: PASS, including the existing Edit-related suites.

- [ ] **Step 6: Commit**

```bash
git add Nimbus/Nimbus/Views/Remotes/ConfigFieldView.swift \
        Nimbus/Nimbus/Views/Remotes/EditRemoteSheet.swift \
        Nimbus/NimbusTests/ConfigFieldViewTests.swift Nimbus/Nimbus.xcodeproj
git commit -m "refactor(remotes): extract ConfigFieldView, render Sensitive options securely"
```

---

### Task 7: ConfigPageForm and OAuthStep

**Files:**
- Create: `Nimbus/Nimbus/Views/Remotes/ConfigPageForm.swift`
- Create: `Nimbus/Nimbus/Views/Remotes/OAuthStep.swift`

**Interfaces:**
- Consumes: `ConfigPage`, `ConfigPage.Boundary` (Task 4); `ConfigFieldView` (Task 6); existing `FormSection`, `FormRow`, `ProviderBadge`, `DesignSystem`.
- Produces: `ConfigPageForm(page:answers:onAnswerChanged:includeAdvanced:showAllOptions:)`, `OAuthStep(provider:isWaiting:onSignIn:onCancel:)`.

- [ ] **Step 1: Implement ConfigPageForm**

Create `Nimbus/Nimbus/Views/Remotes/ConfigPageForm.swift`:

```swift
import SwiftUI
import RcloneKit

/// Renders one batched page of rclone config questions, plus the two mode
/// toggles. The questions come from rclone's own walk, so there is no
/// hand-maintained per-provider field list to keep in sync.
struct ConfigPageForm: View {
    let page: ConfigPage
    @Binding var answers: [String: String]
    @Binding var showAllOptions: Bool
    @Binding var includeAdvanced: Bool
    let onAnswerChanged: (ConfigQuestion, String) -> Void

    private var visibleQuestions: [ConfigQuestion] {
        page.questions.filter { ConfigFieldView.shouldRender($0.option) }
    }

    private var showsAdvancedGate: Bool {
        if case .advancedGate = page.boundary { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            if !visibleQuestions.isEmpty {
                FormSection(title: "Configuration", footer: nil) {
                    ForEach(visibleQuestions, id: \.option.name) { question in
                        FormRow(
                            label: LocalizedStringKey(question.option.name),
                            help: question.option.help.isEmpty
                                ? nil
                                : LocalizedStringKey(question.option.help)
                        ) {
                            ConfigFieldView(
                                option: question.option,
                                value: binding(for: question)
                            )
                        }
                    }
                }
            }

            FormSection(title: "Options", footer: nil) {
                FormRow(
                    label: "Show all options",
                    help: "Ask every question this service supports, not just the essentials."
                ) {
                    Toggle("", isOn: $showAllOptions)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if showsAdvancedGate {
                    FormRow(
                        label: "Edit advanced config",
                        help: "Tuning options most people never need."
                    ) {
                        Toggle("", isOn: $includeAdvanced)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }
        }
    }

    private func binding(for question: ConfigQuestion) -> Binding<String> {
        Binding(
            get: { answers[question.option.name] ?? question.option.defaultValue },
            set: { onAnswerChanged(question, $0) }
        )
    }
}
```

- [ ] **Step 2: Implement OAuthStep**

Create `Nimbus/Nimbus/Views/Remotes/OAuthStep.swift`:

```swift
import SwiftUI
import RcloneKit

/// The sign-in step for OAuth backends. rclone owns the browser handoff: it
/// binds 127.0.0.1:53682 and opens the user's browser itself, which works
/// because Nimbus is not sandboxed. The RC call blocks until the callback
/// arrives, so this view is mostly a waiting state with a working Cancel.
struct OAuthStep: View {
    let provider: Provider
    let isWaiting: Bool
    let onSignIn: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.l) {
            ProviderBadge(provider: provider.prefix, size: 48)

            Text(verbatim: provider.description)
                .font(DesignSystem.Typography.title)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)

            if isWaiting {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for your browser…")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                Button("Cancel", action: onCancel)
                    .accessibilityHint("Stops waiting and discards the partial remote.")
            } else {
                Button("Sign In", action: onSignIn)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Text("Opens your browser. Nimbus never sees your password.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Sign in to \(provider.description)"))
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd Nimbus && xcodegen generate && cd .. && xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

`ProviderBadge` is declared in `Nimbus/Nimbus/Components/ProviderIcon.swift:39-41` as `provider: String` plus `var size: CGFloat = 28`, so `size: 48` is valid.

- [ ] **Step 4: Commit**

```bash
git add Nimbus/Nimbus/Views/Remotes/ConfigPageForm.swift \
        Nimbus/Nimbus/Views/Remotes/OAuthStep.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(remotes): add ConfigPageForm and OAuthStep views"
```

---

### Task 8: Rewrite AddRemoteSheet, delete ConfigForm

**Files:**
- Rewrite: `Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift`
- Delete: `Nimbus/Nimbus/Views/Remotes/ConfigForm.swift`

**Interfaces:**
- Consumes: everything from Tasks 4-7.
- Produces: `AddRemoteSheet(client:onDismiss:)` — signature unchanged, so `RemotesSidebarSection.swift:73` and `OnboardingView.swift:40` keep compiling untouched.

- [ ] **Step 1: Confirm nothing imports ConfigForm**

Run: `grep -rn "ConfigForm" --include="*.swift" Nimbus/`
Expected: matches only in comments (`EditRemoteSheet.swift:25,86,95`) and in `AddRemoteSheet.swift` / `ConfigForm.swift` themselves. If any other file *uses* the type, stop and reassess.

- [ ] **Step 2: Rewrite the sheet**

Replace `Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift` entirely:

```swift
import SwiftUI
import RcloneKit

struct AddRemoteSheet: View {
    let client: RcloneClient
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var providers: [Provider] = []
    @State private var flow: RemoteSetupFlow?
    @State private var existingNames: Set<String> = []
    @State private var error: NimbusError?
    @State private var loadingProviders = true

    var body: some View {
        SheetChrome(
            title: "Add Remote",
            subtitle: nil,
            body: { content },
            actions: { actions }
        )
        .frame(width: 560, height: 560)
        .task { await loadProviders() }
        .alert(
            "Couldn't add remote",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            ),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(verbatim: err.message)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        if loadingProviders {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let flow {
            flowContent(flow)
        } else {
            ProviderPicker(providers: providers) { provider in
                self.flow = RemoteSetupFlow(provider: provider, client: client)
            }
        }
    }

    @ViewBuilder
    private func flowContent(_ flow: RemoteSetupFlow) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            identityHeader(flow.provider)

            switch flow.phase {
            case .naming:
                FormSection(title: "Remote", footer: nameFooter(flow)) {
                    FormRow(label: "Name", help: "Used to reference this remote in the Browser.") {
                        TextField("e.g. gdrive", text: Binding(
                            get: { flow.name },
                            set: { flow.name = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    }
                }
            case .loading, .creating:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            case .page(let page):
                ConfigPageForm(
                    page: page,
                    answers: Binding(get: { flow.answers }, set: { flow.answers = $0 }),
                    showAllOptions: Binding(
                        get: { flow.showAllOptions },
                        set: { flow.showAllOptions = $0; Task { await flow.rewalk() } }
                    ),
                    includeAdvanced: Binding(
                        get: { flow.includeAdvanced },
                        set: { flow.includeAdvanced = $0 }
                    ),
                    onAnswerChanged: { question, value in
                        Task { await flow.answerChanged(question, to: value) }
                    }
                )
            case .signingIn:
                OAuthStep(
                    provider: flow.provider,
                    isWaiting: true,
                    onSignIn: {},
                    onCancel: { Task { await flow.cancel(); self.flow = nil } }
                )
            case .finished:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .task {
                        onDismiss()
                        dismiss()
                    }
            case .failed(let message):
                EmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Setup Failed",
                    messageVerbatim: message,
                    action: .init(label: "Start Over", perform: { self.flow = nil })
                )
            }
        }
    }

    private func identityHeader(_ provider: Provider) -> some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            ProviderBadge(provider: provider.prefix, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: provider.description)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                Text(verbatim: provider.name)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
        }
    }

    private func nameFooter(_ flow: RemoteSetupFlow) -> LocalizedStringKey? {
        nameCollides(flow) ? "A remote with that name already exists." : nil
    }

    private func nameCollides(_ flow: RemoteSetupFlow) -> Bool {
        existingNames.contains(flow.name.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if let flow {
            Button("Back") {
                Task { await flow.cancel(); self.flow = nil }
            }
            Button("Cancel") {
                Task { await flow.cancel(); dismiss() }
            }
            .keyboardShortcut(.cancelAction)

            switch flow.phase {
            case .naming:
                Button("Continue") { Task { await flow.begin() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isNameValid(flow))
            case .page:
                Button("Add Remote") { Task { await flow.submitPage() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            default:
                EmptyView()
            }
        } else {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func isNameValid(_ flow: RemoteSetupFlow) -> Bool {
        let trimmed = flow.name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !existingNames.contains(trimmed)
    }

    // MARK: - Loading

    private func loadProviders() async {
        do {
            providers = try await client.getProviders()
            existingNames = Set(try await client.listRemotes())
        } catch {
            self.error = NimbusError.classify(error)
        }
        loadingProviders = false
    }
}
```

- [ ] **Step 3: Delete the superseded form**

```bash
git rm Nimbus/Nimbus/Views/Remotes/ConfigForm.swift
```

- [ ] **Step 4: Regenerate and build**

Run: `cd Nimbus && xcodegen generate && cd .. && xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

`EmptyState` has two inits (`Nimbus/Nimbus/Components/EmptyState.swift:16,27`); the `messageVerbatim:` one used here exists and takes `action: ActionConfig?` built as `.init(label:perform:)`.

- [ ] **Step 5: Run the whole suite**

Run: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test && swift test --package-path RcloneKit`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A Nimbus/Nimbus/Views/Remotes Nimbus/Nimbus.xcodeproj
git commit -m "feat(remotes): guided Add Remote sheet, drop static ConfigForm"
```

---

### Task 9: Snapshot coverage for the three page shapes

Per CLAUDE.md, UI changes are verified visually before being called done.

**Files:**
- Create: `Nimbus/NimbusTests/GuidedAddRemoteSnapshotTests.swift`

**Interfaces:**
- Consumes: `ConfigPageForm`, `OAuthStep`, `ConfigPage`, `SnapshotHelpers.assertSnapshot`.
- Produces: three committed reference PNGs under `Nimbus/NimbusTests/Fixtures/`.

- [ ] **Step 1: Write the snapshot tests**

Create `Nimbus/NimbusTests/GuidedAddRemoteSnapshotTests.swift`:

```swift
import Testing
import SwiftUI
import Foundation
import RcloneKit
@testable import Nimbus

@Suite("GuidedAddRemote", .serialized)
@MainActor
struct GuidedAddRemoteSnapshotTests {

    private func question(
        _ name: String, help: String = "", type: String = "string",
        sensitive: Bool = false, examples: String? = nil
    ) -> ConfigQuestion {
        let examplesJSON = examples.map { #", "Examples": \#($0)"# } ?? ""
        let json = #"""
        {"Name": "\#(name)", "Help": "\#(help)", "Type": "\#(type)",
         "Required": false, "IsPassword": false, "Advanced": false,
         "Sensitive": \#(sensitive), "Hide": 0, "Exclusive": false,
         "Default": "", "DefaultStr": "", "Value": null\#(examplesJSON)}
        """#
        let option = try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
        return ConfigQuestion(option: option, state: "s")
    }

    private func provider(_ name: String, _ description: String) -> Provider {
        let json = #"{"Name":"\#(name)","Description":"\#(description)","Prefix":"\#(name)","Options":[]}"#
        return try! JSONDecoder().decode(Provider.self, from: Data(json.utf8))
    }

    private func form(_ page: ConfigPage) -> some View {
        ConfigPageForm(
            page: page,
            answers: .constant([:]),
            showAllOptions: .constant(false),
            includeAdvanced: .constant(false),
            onAnswerChanged: { _, _ in }
        )
        .frame(width: 520)
        .padding()
    }

    @Test func oauthBasicShape() throws {
        let view = OAuthStep(
            provider: provider("drive", "Google Drive"),
            isWaiting: false,
            onSignIn: {},
            onCancel: {}
        )
        .frame(width: 520)
        .padding()
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 552, height: 320), named: "AddRemote-oauth-basic"
        )
    }

    @Test func credentialBasicShape() throws {
        let page = ConfigPage(
            questions: [
                question("host", help: "SSH host to connect to."),
                question("user", help: "SSH username."),
                question("port", help: "SSH port number."),
                question("pass", help: "SSH password.", sensitive: true),
            ],
            boundary: .advancedGate(question("config_fs_advanced"))
        )
        try SnapshotHelpers.assertSnapshot(
            form(page), size: CGSize(width: 552, height: 560), named: "AddRemote-credential-basic"
        )
    }

    @Test func showAllShape() throws {
        let page = ConfigPage(
            questions: [
                question("provider", help: "Choose your S3 provider.",
                         examples: #"[{"Value":"AWS","Help":"Amazon Web Services"}]"#),
                question("access_key_id", help: "AWS Access Key ID."),
                question("secret_access_key", help: "AWS Secret Access Key.", sensitive: true),
                question("region", help: "Region to connect to.",
                         examples: #"[{"Value":"us-east-1","Help":"US East"}]"#),
                question("endpoint", help: "Endpoint for S3 API."),
            ],
            boundary: .advancedGate(question("config_fs_advanced"))
        )
        try SnapshotHelpers.assertSnapshot(
            form(page), size: CGSize(width: 552, height: 640), named: "AddRemote-showall-s3"
        )
    }
}
```

- [ ] **Step 2: Run to generate references**

Run: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test -only-testing:NimbusTests/GuidedAddRemote`
Expected: first run writes reference PNGs into `Nimbus/NimbusTests/Fixtures/` (follow whatever `SnapshotHelpers.assertSnapshot` does on a missing reference — check `FileGridLayoutTests.swift` for the established pattern).

- [ ] **Step 3: Inspect the three PNGs by eye**

Open each generated PNG. Confirm: the OAuth shape shows a badge, a prominent Sign In button, and the privacy line; the credential shape shows four rows with `pass` masked; the show-all shape shows pickers for `provider` and `region` and a masked `secret_access_key`. A snapshot test pins whatever it is given — including a broken layout — so this visual check is the actual gate.

- [ ] **Step 4: Re-run to confirm stability**

Run: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test -only-testing:NimbusTests/GuidedAddRemote`
Expected: PASS against the committed references.

- [ ] **Step 5: Commit**

```bash
git add Nimbus/NimbusTests/GuidedAddRemoteSnapshotTests.swift Nimbus/NimbusTests/Fixtures Nimbus/Nimbus.xcodeproj
git commit -m "test(remotes): snapshot the three guided Add Remote page shapes"
```

---

### Task 10: rclone integration canary

Pins the measured behavior the whole design rests on, so an rclone upgrade that changes it fails loudly here rather than silently in the UI.

**Files:**
- Create: `Nimbus/NimbusTests/RcloneConfigMachineTests.swift`

**Interfaces:**
- Consumes: a real `rclone` binary on PATH. Skipped when absent.
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Write the canary**

Create `Nimbus/NimbusTests/RcloneConfigMachineTests.swift`:

```swift
import Testing
import Foundation

/// Pins the rclone behavior the guided Add Remote flow depends on. Skipped
/// when rclone isn't installed. Uses `rclone rc --loopback`, which runs the
/// RC method in-process against a throwaway config file — no daemon needed.
@Suite("RcloneConfigMachine", .serialized)
struct RcloneConfigMachineTests {

    private static var rclonePath: String? {
        let candidates = ["/usr/local/bin/rclone", "/opt/homebrew/bin/rclone"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func loopback(_ configPath: String, _ args: [String]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.rclonePath!)
        process.arguments = ["rc", "--loopback"] + args
        var env = ProcessInfo.processInfo.environment
        env["RCLONE_CONFIG"] = configPath
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Walks the machine with default answers, returning the questions asked.
    private func walk(type: String, askAll: Bool, answers: [String: String]) throws -> [String] {
        let configPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).conf").path
        FileManager.default.createFile(atPath: configPath, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        var asked: [String] = []
        var opt: [String: Any] = ["nonInteractive": true, "all": askAll]
        for _ in 0..<200 {
            let optJSON = String(
                data: try JSONSerialization.data(withJSONObject: opt), encoding: .utf8
            )!
            let response = try loopback(configPath, [
                "config/create", "name=canary", "type=\(type)",
                "parameters={}", "opt=\(optJSON)",
            ])
            let state = response["State"] as? String ?? ""
            guard let option = response["Option"] as? [String: Any],
                  !state.isEmpty else { break }
            let name = option["Name"] as? String ?? "?"
            asked.append(name)
            opt = [
                "nonInteractive": true, "all": askAll, "continue": true,
                "state": state, "result": answers[name] ?? "",
            ]
        }
        return asked
    }

    @Test func askAllWalksAreShortBecauseRcloneGatesByProvider() throws {
        try withKnownIssue(when: Self.rclonePath == nil) {
            #expect(try walk(type: "s3", askAll: true,
                             answers: ["provider": "AWS", "env_auth": "false"]).count == 13)
            #expect(try walk(type: "drive", askAll: true, answers: [:]).count == 8)
            #expect(try walk(type: "sftp", askAll: true, answers: [:]).count == 14)
        }
    }

    @Test func askAllTrueWalksEndAtTheAdvancedGate() throws {
        try withKnownIssue(when: Self.rclonePath == nil) {
            let asked = try walk(type: "s3", askAll: true,
                                 answers: ["provider": "AWS", "env_auth": "false"])
            #expect(asked.last == "config_fs_advanced")
        }
    }

    @Test func askAllFalseReachesOAuthOnDriveAndAsksNothingOnSftp() throws {
        try withKnownIssue(when: Self.rclonePath == nil) {
            // The asymmetry the flow's strategy selection depends on.
            #expect(try walk(type: "drive", askAll: false, answers: [:]).first == "config_is_local")
            #expect(try walk(type: "sftp", askAll: false, answers: [:]).isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run**

Run: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test -only-testing:NimbusTests/RcloneConfigMachine`
Expected: PASS on a machine with rclone 1.74.

If a count differs, do **not** just update the number — a changed count means rclone changed which questions it asks, and the flow's behavior needs re-checking. Record the new counts and note the rclone version.

- [ ] **Step 3: Commit**

```bash
git add Nimbus/NimbusTests/RcloneConfigMachineTests.swift Nimbus/Nimbus.xcodeproj
git commit -m "test(remotes): pin rclone config machine behavior as an upgrade canary"
```

---

### Task 11: End-to-end manual verification

Automated tests never exercise a real browser handoff or a real `rclone.conf`. This task is the one that proves the feature works.

**Files:** none.

- [ ] **Step 1: Back up the real config**

```bash
cp ~/.config/rclone/rclone.conf ~/.config/rclone/rclone.conf.bak-$(date +%Y%m%d)
```

- [ ] **Step 2: Launch and add an OAuth remote**

Run: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build` then launch the built app.

Add a Google Drive remote. Confirm: the sheet asks for a name, then shows Sign In — **not** `client_id` / `client_secret` fields. Confirm the browser opens, sign-in completes, the sheet closes, and the remote browses real files.

- [ ] **Step 3: Add a credential remote with Show All Options**

Add an S3 remote. Confirm the basic page shows host/credential fields (not an empty page — an empty page here means `all:false` leaked through and would write a stub). Toggle **Show all options** and confirm the page re-walks and grows. Toggle **Edit advanced config** and confirm the advanced questions appear.

- [ ] **Step 4: Verify cleanup on every abort path**

For each of: Back from the name step, Cancel from a config page, Cancel during OAuth waiting, and closing the sheet with the window control — run afterwards:

```bash
grep -c "^\[" ~/.config/rclone/rclone.conf
rclone config dump | python3 -m json.tool | grep -A2 '"type"'
```

Expected: no leftover remote whose only key is `type`. A stub means `cleanUpPartialRemote` missed a path.

- [ ] **Step 5: Verify the branching re-walk**

In an S3 remote, change **provider** from AWS to another value. Confirm the field set changes and that previously entered credentials are still populated.

- [ ] **Step 6: Full suite green**

Run: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test && swift test --package-path RcloneKit`
Expected: PASS.

- [ ] **Step 7: Commit any fixes**

```bash
git add -A
git commit -m "fix(remotes): address issues found in end-to-end verification"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| ConfigSession, ConfigStep, ConfigQuestion | 3 |
| `Sensitive`/`Hide`/`Exclusive`/`DefaultStr` on ProviderOption | 2 |
| Dedicated long-lived session for config calls | 3 (step 5) |
| RemoteSetupFlow, Phase, ConfigPage | 4 |
| Strategy selection by `*oauth` prefix | 4 |
| Page batching | 4 |
| Re-walk on `Exclusive` | 5 |
| ConfigPageForm, OAuthStep, ConfigFieldView | 6, 7 |
| AddRemoteSheet rewrite, ConfigForm deleted | 8 |
| EditRemoteSheet adopts ConfigFieldView | 6 |
| Partial-remote cleanup on every abort | 4 (tested), 11 (verified live) |
| Error inside 200 | 3 |
| Name collision check via `config/listremotes` | 8 |
| Unit tests on fixtures | 1-6 |
| Integration canary | 10 |
| RenderPreview / snapshot on three shapes | 9 |
| Manual against a real account | 11 |

No gaps.

**Deviation from spec, deliberate:** the spec's verification section says `RenderPreview`. Task 9 uses the repo's existing `SnapshotHelpers` harness instead, because that is the established pattern in `NimbusTests` (`ProviderPickerTests`, `FileGridLayoutTests`) and it runs in CI. Step 3 of that task keeps the human eye-check that `RenderPreview` would have provided.

**Placeholder scan:** no TBDs; every code step carries real code; no "similar to Task N".

**Type consistency:** `ConfigStep`, `ConfigQuestion`, `ConfigPage`, `ConfigPage.Boundary`, `RemoteSetupFlow.Phase`, `RemoteConfigDriving`, `ConfigFieldView.isSecure`/`shouldRender`, `answerChanged(_:to:)`, `rewalk()`, `submitPage()`, `begin()`, `cancel()`, `deletePartialRemote(name:)` are each defined once and referenced consistently. `ScriptedConfigClient` conforms to `RemoteConfigDriving` (Task 4), which `RcloneClient` also conforms to via the extension in the same file.

**Known risk, flagged in the design:** page batching plus replay is the least-proven part. If replay proves unreliable against real rclone in Task 11, the fallback is a stepped wizard — one question per screen, no speculative walking — which is a `ConfigPageForm` change only; `ConfigSession` and `RemoteSetupFlow` stay as they are.
