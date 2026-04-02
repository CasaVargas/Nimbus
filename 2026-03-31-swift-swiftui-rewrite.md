# Swift/SwiftUI Native Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite Nimbus from Tauri 2 (Rust + React + TypeScript) to a native Swift/SwiftUI macOS app, retaining rclone as the cloud storage backend.

**Architecture:** MVVM with a shared RcloneKit Swift Package used by both the main app and File Provider extension. Services layer (RcloneDaemon, MountManager, FileProviderBridge) replaces the Rust backend. SwiftUI views bind to @Observable view models.

**Tech Stack:** Swift 6, SwiftUI, macOS 15+, URLSession, Codable, @Observable, NSFileProviderManager, Process API

**Spec:** `docs/superpowers/specs/2026-03-31-swift-swiftui-rewrite-design.md`

---

## File Structure

### RcloneKit (Local Swift Package)

| File | Responsibility |
|------|---------------|
| `RcloneKit/Package.swift` | Package manifest, platforms: macOS 15+ |
| `RcloneKit/Sources/RcloneKit/Models.swift` | All Codable types: FileItem, Remote, Provider, ProviderOption, Job, TransferStats, etc. |
| `RcloneKit/Sources/RcloneKit/RcloneClient.swift` | Base HTTP client: URLSession POST to localhost, error handling, health check |
| `RcloneKit/Sources/RcloneKit/Operations.swift` | File operations: list, stat, mkdir, delete, purge, move, copy, about |
| `RcloneKit/Sources/RcloneKit/Remotes.swift` | Remote config: list, dump, providers, create, update, delete |
| `RcloneKit/Sources/RcloneKit/Sync.swift` | Bulk operations: copy, sync (async jobs) |
| `RcloneKit/Sources/RcloneKit/Jobs.swift` | Job monitoring: list, status, stop |
| `RcloneKit/Sources/RcloneKit/Stats.swift` | Transfer statistics: getStats, bandwidth limit |
| `RcloneKit/Tests/RcloneKitTests/ModelsTests.swift` | JSON decoding tests for all model types |
| `RcloneKit/Tests/RcloneKitTests/RcloneClientTests.swift` | HTTP client tests with mock URLProtocol |
| `RcloneKit/Tests/RcloneKitTests/OperationsTests.swift` | Operations endpoint tests |
| `RcloneKit/Tests/RcloneKitTests/RemotesTests.swift` | Remotes endpoint tests |

### Nimbus App

| File | Responsibility |
|------|---------------|
| `Nimbus/NimbusApp.swift` | @main, WindowGroup, MenuBarExtra, app lifecycle, service injection |
| `Nimbus/Services/RcloneDaemon.swift` | Process lifecycle for rclone rcd, health check, port scanning |
| `Nimbus/Services/MountManager.swift` | NFS mount/unmount, port allocation, health monitoring, cleanup |
| `Nimbus/Services/FileProviderBridge.swift` | NSFileProviderManager domain CRUD, app group state sync |
| `Nimbus/State/AppSettings.swift` | @Observable with @AppStorage: theme, port, paths, onboarding flag |
| `Nimbus/State/MountConfiguration.swift` | Codable mount configs persisted to Application Support |
| `Nimbus/State/TransferStore.swift` | @Observable in-memory transfer tracking with job polling |
| `Nimbus/Views/Sidebar.swift` | NavigationSplitView sidebar with section list |
| `Nimbus/Views/ContentView.swift` | Root view: onboarding gate + NavigationSplitView shell |
| `Nimbus/Views/Browser/BrowserView.swift` | Container: toolbar + breadcrumb + file list/grid |
| `Nimbus/Views/Browser/FileTable.swift` | Table view with sortable columns, multi-selection |
| `Nimbus/Views/Browser/FileGrid.swift` | LazyVGrid with file icons |
| `Nimbus/Views/Browser/BrowserToolbar.swift` | Toolbar: view mode, sort, upload, new folder |
| `Nimbus/Views/Browser/FileContextMenu.swift` | Context menu modifier for file actions |
| `Nimbus/Views/Remotes/RemotesView.swift` | List of remote cards with add/edit/delete |
| `Nimbus/Views/Remotes/RemoteRow.swift` | Single remote display with actions |
| `Nimbus/Views/Remotes/AddRemoteSheet.swift` | Provider picker → dynamic config form |
| `Nimbus/Views/Remotes/EditRemoteSheet.swift` | Pre-filled config form for editing |
| `Nimbus/Views/Remotes/ConfigForm.swift` | Dynamic form from provider option schema |
| `Nimbus/Views/Mounts/MountsView.swift` | List of mount configs with status |
| `Nimbus/Views/Mounts/MountRow.swift` | Mount row with mount/unmount toggle |
| `Nimbus/Views/Mounts/AddMountSheet.swift` | Form: remote picker, path, VFS mode |
| `Nimbus/Views/Transfers/TransfersView.swift` | Active + completed transfers list |
| `Nimbus/Views/Transfers/TransferRow.swift` | Progress bar, speed, ETA, cancel |
| `Nimbus/Views/CopySync/CopySyncView.swift` | Source/dest pickers, operation toggle |
| `Nimbus/Views/CopySync/PathPicker.swift` | Remote + path browser picker |
| `Nimbus/Views/Settings/SettingsView.swift` | TabView with settings sections |
| `Nimbus/Views/Settings/AppearanceSection.swift` | Theme picker |
| `Nimbus/Views/Settings/TransferSection.swift` | Bandwidth, concurrent transfers |
| `Nimbus/Views/Settings/RcloneSection.swift` | Binary path, port |
| `Nimbus/Views/Settings/AboutSection.swift` | Version, links |
| `Nimbus/Views/Onboarding/OnboardingView.swift` | Multi-step first-run wizard |
| `Nimbus/ViewModels/BrowserViewModel.swift` | File listing, navigation stack, file operations |
| `Nimbus/ViewModels/RemotesViewModel.swift` | Remote CRUD, provider loading |
| `Nimbus/ViewModels/MountsViewModel.swift` | Mount lifecycle, active mount queries |
| `Nimbus/ViewModels/TransfersViewModel.swift` | Job polling, stats aggregation |
| `Nimbus/ViewModels/CopySyncViewModel.swift` | Copy/sync job dispatch |

### File Provider Extension (Refactored)

| File | Responsibility |
|------|---------------|
| `FileProviderExtension/Extension.swift` | NSFileProviderReplicatedExtension, uses RcloneKit |
| `FileProviderExtension/Enumerator.swift` | Directory enumeration + change diffing |
| `FileProviderExtension/Item.swift` | NSFileProviderItem mapping from RcloneKit.FileItem |

---

## Task 1: Xcode Project & RcloneKit Package Setup

**Files:**
- Create: `Nimbus/Nimbus.xcodeproj` (via Xcode)
- Create: `RcloneKit/Package.swift`
- Create: `RcloneKit/Sources/RcloneKit/RcloneKit.swift` (placeholder)
- Create: `Nimbus/NimbusApp.swift` (minimal)

- [ ] **Step 1: Create RcloneKit Swift Package**

```bash
cd /Volumes/DATA/Dev/Nimbus
mkdir -p RcloneKit/Sources/RcloneKit
mkdir -p RcloneKit/Tests/RcloneKitTests
```

Write `RcloneKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RcloneKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RcloneKit", targets: ["RcloneKit"]),
    ],
    targets: [
        .target(name: "RcloneKit"),
        .testTarget(name: "RcloneKitTests", dependencies: ["RcloneKit"]),
    ]
)
```

Write `RcloneKit/Sources/RcloneKit/RcloneKit.swift`:

```swift
// RcloneKit — Typed HTTP client for the rclone RC API
```

Write `RcloneKit/Tests/RcloneKitTests/RcloneKitTests.swift`:

```swift
import Testing
@testable import RcloneKit

@Test func packageLoads() {
    // RcloneKit package loads successfully
}
```

- [ ] **Step 2: Verify RcloneKit builds**

```bash
cd /Volumes/DATA/Dev/Nimbus/RcloneKit
swift build
swift test
```

Expected: Build succeeds, 1 test passes.

- [ ] **Step 3: Create Xcode project**

Open Xcode → File → New → Project → macOS → App:
- Product Name: `Nimbus`
- Team: Your development team
- Organization Identifier: `com.nimbus`
- Interface: SwiftUI
- Language: Swift
- Testing: Swift Testing

Save the project at `/Volumes/DATA/Dev/Nimbus/Nimbus/`.

Then in Xcode:
- File → Add Package Dependencies → Add Local → select `RcloneKit/`
- Add `RcloneKit` library to the Nimbus app target

- [ ] **Step 4: Write minimal NimbusApp.swift**

Replace the generated `NimbusApp.swift` with:

```swift
import SwiftUI

@main
struct NimbusApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Nimbus")
                .frame(width: 800, height: 600)
        }
    }
}
```

- [ ] **Step 5: Build and run**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

Expected: App builds, launches with "Nimbus" text.

- [ ] **Step 6: Commit**

```bash
git add RcloneKit/ Nimbus/
git commit -m "feat: scaffold Xcode project and RcloneKit Swift Package"
```

---

## Task 2: RcloneKit Models

**Files:**
- Create: `RcloneKit/Sources/RcloneKit/Models.swift`
- Create: `RcloneKit/Tests/RcloneKitTests/ModelsTests.swift`

- [ ] **Step 1: Write model decoding tests**

Write `RcloneKit/Tests/RcloneKitTests/ModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import RcloneKit

@Test func decodesFileItem() throws {
    let json = """
    {
        "Path": "documents/report.pdf",
        "Name": "report.pdf",
        "Size": 1048576,
        "MimeType": "application/pdf",
        "ModTime": "2026-03-31T10:00:00.000000000Z",
        "IsDir": false,
        "ID": "abc123"
    }
    """.data(using: .utf8)!

    let item = try JSONDecoder().decode(FileItem.self, from: json)
    #expect(item.path == "documents/report.pdf")
    #expect(item.name == "report.pdf")
    #expect(item.size == 1_048_576)
    #expect(item.mimeType == "application/pdf")
    #expect(item.isDir == false)
    #expect(item.id == "abc123")
    #expect(item.modTime != nil)
}

@Test func decodesFileItemDirectory() throws {
    let json = """
    {
        "Path": "photos",
        "Name": "photos",
        "Size": -1,
        "MimeType": "inode/directory",
        "ModTime": "2026-03-31T10:00:00.000000000Z",
        "IsDir": true
    }
    """.data(using: .utf8)!

    let item = try JSONDecoder().decode(FileItem.self, from: json)
    #expect(item.isDir == true)
    #expect(item.id == nil)
}

@Test func decodesProvider() throws {
    let json = """
    {
        "Name": "s3",
        "Description": "Amazon S3",
        "Prefix": "s3",
        "Options": [
            {
                "Name": "access_key_id",
                "Help": "AWS Access Key ID",
                "Default": "",
                "Value": "",
                "Type": "string",
                "Required": true,
                "IsPassword": false,
                "Advanced": false
            },
            {
                "Name": "secret_access_key",
                "Help": "AWS Secret Access Key",
                "Default": "",
                "Value": "",
                "Type": "string",
                "Required": true,
                "IsPassword": true,
                "Advanced": false
            }
        ]
    }
    """.data(using: .utf8)!

    let provider = try JSONDecoder().decode(Provider.self, from: json)
    #expect(provider.name == "s3")
    #expect(provider.description == "Amazon S3")
    #expect(provider.options.count == 2)
    #expect(provider.options[0].required == true)
    #expect(provider.options[1].isPassword == true)
}

@Test func decodesProviderOptionWithExamples() throws {
    let json = """
    {
        "Name": "region",
        "Help": "Region to connect to",
        "Default": "",
        "Value": "",
        "Type": "string",
        "Required": false,
        "IsPassword": false,
        "Advanced": false,
        "Examples": [
            {"Value": "us-east-1", "Help": "US East (N. Virginia)"},
            {"Value": "eu-west-1", "Help": "EU (Ireland)"}
        ]
    }
    """.data(using: .utf8)!

    let option = try JSONDecoder().decode(ProviderOption.self, from: json)
    #expect(option.examples?.count == 2)
    #expect(option.examples?[0].value == "us-east-1")
}

@Test func decodesJobStatus() throws {
    let json = """
    {
        "id": 42,
        "group": "job/42",
        "startTime": "2026-03-31T10:00:00Z",
        "endTime": "2026-03-31T10:05:00Z",
        "error": "",
        "finished": true,
        "success": true,
        "duration": 300.0,
        "output": {}
    }
    """.data(using: .utf8)!

    let job = try JSONDecoder().decode(Job.self, from: json)
    #expect(job.id == 42)
    #expect(job.finished == true)
    #expect(job.success == true)
    #expect(job.duration == 300.0)
}

@Test func decodesStatsResponse() throws {
    let json = """
    {
        "speed": 1048576,
        "bytes": 10485760,
        "errors": 0,
        "fatalError": false,
        "checks": 5,
        "transfers": 3,
        "deletes": 0,
        "elapsedTime": 10.5,
        "totalBytes": 52428800,
        "totalTransfers": 10,
        "totalChecks": 20,
        "transferring": [
            {
                "name": "file.zip",
                "size": 5242880,
                "bytes": 2621440,
                "percentage": 50,
                "speed": 524288,
                "speedAvg": 500000,
                "eta": 5,
                "group": "job/42"
            }
        ]
    }
    """.data(using: .utf8)!

    let stats = try JSONDecoder().decode(StatsResponse.self, from: json)
    #expect(stats.speed == 1_048_576)
    #expect(stats.transferring?.count == 1)
    #expect(stats.transferring?[0].percentage == 50)
}

@Test func decodesAboutResponse() throws {
    let json = """
    {
        "total": 16106127360,
        "used": 10737418240,
        "free": 5368709120
    }
    """.data(using: .utf8)!

    let about = try JSONDecoder().decode(AboutResponse.self, from: json)
    #expect(about.total == 16_106_127_360)
    #expect(about.used == 10_737_418_240)
    #expect(about.free == 5_368_709_120)
}

@Test func decodesAboutResponseWithNulls() throws {
    let json = """
    {
        "total": null,
        "used": 500
    }
    """.data(using: .utf8)!

    let about = try JSONDecoder().decode(AboutResponse.self, from: json)
    #expect(about.total == nil)
    #expect(about.used == 500)
    #expect(about.free == nil)
}

@Test func decodesBandwidthLimitResponse() throws {
    let json = """
    {
        "bytesPerSecond": 5242880,
        "bytesPerSecondTx": 5242880,
        "bytesPerSecondRx": 5242880,
        "rate": "5M"
    }
    """.data(using: .utf8)!

    let bw = try JSONDecoder().decode(BandwidthLimitResponse.self, from: json)
    #expect(bw.rate == "5M")
    #expect(bw.bytesPerSecond == 5_242_880)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Volumes/DATA/Dev/Nimbus/RcloneKit
swift test
```

Expected: Compilation errors — types don't exist yet.

- [ ] **Step 3: Implement Models.swift**

Write `RcloneKit/Sources/RcloneKit/Models.swift`:

```swift
import Foundation

// MARK: - File Operations

public struct FileItem: Codable, Identifiable, Sendable {
    public let path: String
    public let name: String
    public let size: Int64
    public let mimeType: String
    public let modTime: Date?
    public let isDir: Bool
    public let id: String?

    public var identifier: String { path }

    enum CodingKeys: String, CodingKey {
        case path = "Path"
        case name = "Name"
        case size = "Size"
        case mimeType = "MimeType"
        case modTime = "ModTime"
        case isDir = "IsDir"
        case id = "ID"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        size = try container.decode(Int64.self, forKey: .size)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        isDir = try container.decode(Bool.self, forKey: .isDir)
        id = try container.decodeIfPresent(String.self, forKey: .id)

        let modTimeString = try container.decodeIfPresent(String.self, forKey: .modTime)
        if let modTimeString {
            modTime = Self.parseModTime(modTimeString)
        } else {
            modTime = nil
        }
    }

    private static func parseModTime(_ string: String) -> Date? {
        // rclone returns nanosecond-precision timestamps like "2026-03-31T10:00:00.000000000Z"
        // ISO8601DateFormatter handles fractional seconds
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Remote Configuration

public struct Remote: Sendable {
    public let name: String
    public let type: String
    public let config: [String: String]

    public init(name: String, type: String, config: [String: String]) {
        self.name = name
        self.type = type
        self.config = config
    }
}

public struct Provider: Codable, Sendable {
    public let name: String
    public let description: String
    public let prefix: String
    public let options: [ProviderOption]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case description = "Description"
        case prefix = "Prefix"
        case options = "Options"
    }
}

public struct ProviderOption: Codable, Sendable, Identifiable {
    public let name: String
    public let help: String
    public let defaultValue: String
    public let value: String
    public let type: String
    public let required: Bool
    public let isPassword: Bool
    public let advanced: Bool
    public let examples: [ProviderExample]?

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case help = "Help"
        case defaultValue = "Default"
        case value = "Value"
        case type = "Type"
        case required = "Required"
        case isPassword = "IsPassword"
        case advanced = "Advanced"
        case examples = "Examples"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        help = try container.decode(String.self, forKey: .help)
        type = try container.decode(String.self, forKey: .type)
        required = try container.decode(Bool.self, forKey: .required)
        isPassword = try container.decode(Bool.self, forKey: .isPassword)
        advanced = try container.decode(Bool.self, forKey: .advanced)
        examples = try container.decodeIfPresent([ProviderExample].self, forKey: .examples)

        // Default and Value can be various types in JSON (string, int, bool, null)
        if let s = try? container.decode(String.self, forKey: .defaultValue) {
            defaultValue = s
        } else if let i = try? container.decode(Int.self, forKey: .defaultValue) {
            defaultValue = String(i)
        } else if let b = try? container.decode(Bool.self, forKey: .defaultValue) {
            defaultValue = String(b)
        } else {
            defaultValue = ""
        }

        if let s = try? container.decode(String.self, forKey: .value) {
            value = s
        } else if let i = try? container.decode(Int.self, forKey: .value) {
            value = String(i)
        } else if let b = try? container.decode(Bool.self, forKey: .value) {
            value = String(b)
        } else {
            value = ""
        }
    }
}

public struct ProviderExample: Codable, Sendable {
    public let value: String
    public let help: String

    enum CodingKeys: String, CodingKey {
        case value = "Value"
        case help = "Help"
    }
}

// MARK: - Jobs

public struct Job: Codable, Sendable, Identifiable {
    public let id: Int
    public let group: String
    public let startTime: String
    public let endTime: String
    public let error: String
    public let finished: Bool
    public let success: Bool
    public let duration: Double
    // output is an arbitrary dict — we don't need to parse it
}

// MARK: - Statistics

public struct StatsResponse: Codable, Sendable {
    public let speed: Double
    public let bytes: Int64
    public let errors: Int
    public let fatalError: Bool?
    public let checks: Int
    public let transfers: Int
    public let deletes: Int
    public let elapsedTime: Double
    public let totalBytes: Int64
    public let totalTransfers: Int
    public let totalChecks: Int
    public let transferring: [TransferringFile]?
    public let checking: [String]?
}

public struct TransferringFile: Codable, Sendable, Identifiable {
    public let name: String
    public let size: Int64
    public let bytes: Int64
    public let percentage: Int
    public let speed: Double
    public let speedAvg: Double
    public let eta: Int?
    public let group: String

    public var id: String { name }
}

public struct BandwidthLimitResponse: Codable, Sendable {
    public let bytesPerSecond: Int64
    public let bytesPerSecondTx: Int64
    public let bytesPerSecondRx: Int64
    public let rate: String
}

// MARK: - Storage Info

public struct AboutResponse: Codable, Sendable {
    public let total: Int64?
    public let used: Int64?
    public let trashed: Int64?
    public let free: Int64?
}

// MARK: - RC API Response Wrappers

public struct ListResponse: Codable, Sendable {
    public let list: [FileItem]
}

public struct StatResponse: Codable, Sendable {
    public let item: FileItem
}

public struct RemoteListResponse: Codable, Sendable {
    public let remotes: [String]
}

public struct ProvidersResponse: Codable, Sendable {
    public let providers: [Provider]
}

public struct AsyncJobResponse: Codable, Sendable {
    public let jobid: Int
}

public struct JobListResponse: Codable, Sendable {
    public let jobids: [Int]
}

// MARK: - Errors

public struct RcloneErrorResponse: Codable, Sendable {
    public let error: String
    public let path: String
    public let status: Int
}

public enum RcloneError: Error, LocalizedError, Sendable {
    case serverNotRunning
    case requestFailed(status: Int, message: String)
    case invalidResponse
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            "Rclone daemon is not running"
        case .requestFailed(let status, let message):
            "Request failed (\(status)): \(message)"
        case .invalidResponse:
            "Invalid response from rclone"
        case .decodingError(let detail):
            "Failed to decode response: \(detail)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Volumes/DATA/Dev/Nimbus/RcloneKit
swift test
```

Expected: All 9 model tests pass.

- [ ] **Step 5: Commit**

```bash
git add RcloneKit/Sources/RcloneKit/Models.swift RcloneKit/Tests/RcloneKitTests/ModelsTests.swift
git commit -m "feat(RcloneKit): add Codable model types for rclone RC API"
```

---

## Task 3: RcloneKit HTTP Client

**Files:**
- Create: `RcloneKit/Sources/RcloneKit/RcloneClient.swift`
- Create: `RcloneKit/Tests/RcloneKitTests/RcloneClientTests.swift`

- [ ] **Step 1: Write client tests with mock URLProtocol**

Write `RcloneKit/Tests/RcloneKitTests/RcloneClientTests.swift`:

```swift
import Foundation
import Testing
@testable import RcloneKit

// Mock URLProtocol for testing HTTP calls without a real server
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponses: [String: (Data, Int)] = [:]

    static func register(endpoint: String, json: String, status: Int = 200) {
        mockResponses[endpoint] = (json.data(using: .utf8)!, status)
    }

    static func reset() {
        mockResponses = [:]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        if let (data, status) = Self.mockResponses[path] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func makeTestClient() -> RcloneClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return RcloneClient(port: 5572, session: session)
}

@Test func healthCheckSuccess() async throws {
    MockURLProtocol.register(endpoint: "rc/noop", json: "{}")
    let client = makeTestClient()
    let healthy = await client.healthCheck()
    #expect(healthy == true)
    MockURLProtocol.reset()
}

@Test func healthCheckFailure() async throws {
    MockURLProtocol.reset()
    // No mock registered → 404
    let client = makeTestClient()
    let healthy = await client.healthCheck()
    #expect(healthy == false)
}

@Test func callDecodesResponse() async throws {
    MockURLProtocol.register(
        endpoint: "config/listremotes",
        json: #"{"remotes": ["gdrive", "s3"]}"#
    )
    let client = makeTestClient()
    let response: RemoteListResponse = try await client.call("config/listremotes")
    #expect(response.remotes == ["gdrive", "s3"])
    MockURLProtocol.reset()
}

@Test func callWithParams() async throws {
    MockURLProtocol.register(
        endpoint: "operations/list",
        json: #"{"list": []}"#
    )
    let client = makeTestClient()
    let response: ListResponse = try await client.call("operations/list", params: [
        "fs": "gdrive:",
        "remote": "documents",
    ])
    #expect(response.list.isEmpty)
    MockURLProtocol.reset()
}

@Test func callThrowsOnErrorStatus() async throws {
    MockURLProtocol.register(
        endpoint: "operations/list",
        json: #"{"error": "directory not found", "path": "operations/list", "status": 404}"#,
        status: 404
    )
    let client = makeTestClient()
    do {
        let _: ListResponse = try await client.call("operations/list")
        #expect(Bool(false), "Should have thrown")
    } catch let error as RcloneError {
        if case .requestFailed(let status, let message) = error {
            #expect(status == 404)
            #expect(message.contains("directory not found"))
        } else {
            #expect(Bool(false), "Wrong error case: \(error)")
        }
    }
    MockURLProtocol.reset()
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Volumes/DATA/Dev/Nimbus/RcloneKit
swift test
```

Expected: Compilation errors — `RcloneClient` doesn't exist yet.

- [ ] **Step 3: Implement RcloneClient.swift**

Write `RcloneKit/Sources/RcloneKit/RcloneClient.swift`:

```swift
import Foundation

public actor RcloneClient {
    public private(set) var port: Int
    private let session: URLSession

    public init(port: Int = 5572, session: URLSession? = nil) {
        self.port = port
        self.session = session ?? {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 300
            return URLSession(configuration: config)
        }()
    }

    public func updatePort(_ newPort: Int) {
        port = newPort
    }

    private var baseURL: String {
        "http://127.0.0.1:\(port)"
    }

    /// Call an rclone RC API endpoint with optional parameters.
    public func call<T: Decodable & Sendable>(
        _ endpoint: String,
        params: [String: any Sendable] = [:]
    ) async throws -> T {
        let url = URL(string: "\(baseURL)/\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !params.isEmpty {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } else {
            request.httpBody = "{}".data(using: .utf8)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RcloneError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(RcloneErrorResponse.self, from: data) {
                throw RcloneError.requestFailed(
                    status: errorResponse.status,
                    message: errorResponse.error
                )
            }
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw RcloneError.requestFailed(
                status: httpResponse.statusCode,
                message: body
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RcloneError.decodingError(error.localizedDescription)
        }
    }

    /// Fire-and-forget call that ignores the response body.
    public func call(
        _ endpoint: String,
        params: [String: any Sendable] = [:]
    ) async throws {
        let _: EmptyResponse = try await call(endpoint, params: params)
    }

    /// Check if the rclone daemon is responsive.
    public func healthCheck() async -> Bool {
        do {
            let _: EmptyResponse = try await call("rc/noop")
            return true
        } catch {
            return false
        }
    }
}

private struct EmptyResponse: Decodable {}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Volumes/DATA/Dev/Nimbus/RcloneKit
swift test
```

Expected: All client tests pass.

- [ ] **Step 5: Commit**

```bash
git add RcloneKit/Sources/RcloneKit/RcloneClient.swift RcloneKit/Tests/RcloneKitTests/RcloneClientTests.swift
git commit -m "feat(RcloneKit): add RcloneClient HTTP actor with mock-based tests"
```

---

## Task 4: RcloneKit Operations, Remotes, Sync, Jobs, Stats

**Files:**
- Create: `RcloneKit/Sources/RcloneKit/Operations.swift`
- Create: `RcloneKit/Sources/RcloneKit/Remotes.swift`
- Create: `RcloneKit/Sources/RcloneKit/Sync.swift`
- Create: `RcloneKit/Sources/RcloneKit/Jobs.swift`
- Create: `RcloneKit/Sources/RcloneKit/Stats.swift`
- Create: `RcloneKit/Tests/RcloneKitTests/OperationsTests.swift`
- Create: `RcloneKit/Tests/RcloneKitTests/RemotesTests.swift`

- [ ] **Step 1: Write operations tests**

Write `RcloneKit/Tests/RcloneKitTests/OperationsTests.swift`:

```swift
import Foundation
import Testing
@testable import RcloneKit

@Test func listFiles() async throws {
    MockURLProtocol.register(
        endpoint: "operations/list",
        json: #"""
        {
            "list": [
                {
                    "Path": "photo.jpg",
                    "Name": "photo.jpg",
                    "Size": 2048,
                    "MimeType": "image/jpeg",
                    "ModTime": "2026-03-31T10:00:00Z",
                    "IsDir": false
                },
                {
                    "Path": "docs",
                    "Name": "docs",
                    "Size": -1,
                    "MimeType": "inode/directory",
                    "ModTime": "2026-03-31T09:00:00Z",
                    "IsDir": true
                }
            ]
        }
        """#
    )
    let client = makeTestClient()
    let files = try await client.listFiles(fs: "gdrive:", remote: "")
    #expect(files.count == 2)
    #expect(files[0].name == "photo.jpg")
    #expect(files[1].isDir == true)
    MockURLProtocol.reset()
}

@Test func mkdir() async throws {
    MockURLProtocol.register(endpoint: "operations/mkdir", json: "{}")
    let client = makeTestClient()
    try await client.mkdir(fs: "gdrive:", remote: "new-folder")
    MockURLProtocol.reset()
}

@Test func deleteFile() async throws {
    MockURLProtocol.register(endpoint: "operations/deletefile", json: "{}")
    let client = makeTestClient()
    try await client.deleteFile(fs: "gdrive:", remote: "old-file.txt")
    MockURLProtocol.reset()
}

@Test func about() async throws {
    MockURLProtocol.register(
        endpoint: "operations/about",
        json: #"{"total": 1000000, "used": 500000, "free": 500000}"#
    )
    let client = makeTestClient()
    let info = try await client.about(fs: "gdrive:")
    #expect(info.total == 1_000_000)
    #expect(info.used == 500_000)
    MockURLProtocol.reset()
}
```

- [ ] **Step 2: Write remotes tests**

Write `RcloneKit/Tests/RcloneKitTests/RemotesTests.swift`:

```swift
import Foundation
import Testing
@testable import RcloneKit

@Test func listRemotes() async throws {
    MockURLProtocol.register(
        endpoint: "config/listremotes",
        json: #"{"remotes": ["gdrive", "s3", "dropbox"]}"#
    )
    let client = makeTestClient()
    let remotes = try await client.listRemotes()
    #expect(remotes == ["gdrive", "s3", "dropbox"])
    MockURLProtocol.reset()
}

@Test func configDump() async throws {
    MockURLProtocol.register(
        endpoint: "config/dump",
        json: #"{"gdrive": {"type": "drive", "token": "abc"}, "s3": {"type": "s3", "region": "us-east-1"}}"#
    )
    let client = makeTestClient()
    let dump = try await client.configDump()
    #expect(dump["gdrive"]?["type"] == "drive")
    #expect(dump["s3"]?["region"] == "us-east-1")
    MockURLProtocol.reset()
}

@Test func getProviders() async throws {
    MockURLProtocol.register(
        endpoint: "config/providers",
        json: #"{"providers": [{"Name": "s3", "Description": "Amazon S3", "Prefix": "s3", "Options": []}]}"#
    )
    let client = makeTestClient()
    let providers = try await client.getProviders()
    #expect(providers.count == 1)
    #expect(providers[0].name == "s3")
    MockURLProtocol.reset()
}

@Test func createRemote() async throws {
    MockURLProtocol.register(endpoint: "config/create", json: "{}")
    let client = makeTestClient()
    try await client.createRemote(name: "myremote", type: "s3", parameters: ["region": "us-east-1"])
    MockURLProtocol.reset()
}

@Test func deleteRemote() async throws {
    MockURLProtocol.register(endpoint: "config/delete", json: "{}")
    let client = makeTestClient()
    try await client.deleteRemote(name: "oldremote")
    MockURLProtocol.reset()
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd /Volumes/DATA/Dev/Nimbus/RcloneKit
swift test
```

Expected: Compilation errors — methods don't exist on `RcloneClient`.

- [ ] **Step 4: Implement Operations.swift**

Write `RcloneKit/Sources/RcloneKit/Operations.swift`:

```swift
import Foundation

extension RcloneClient {

    /// List files in a directory.
    public func listFiles(fs: String, remote: String) async throws -> [FileItem] {
        let response: ListResponse = try await call("operations/list", params: [
            "fs": fs,
            "remote": remote,
        ])
        return response.list
    }

    /// Get metadata for a single file.
    public func stat(fs: String, remote: String) async throws -> FileItem {
        let response: StatResponse = try await call("operations/stat", params: [
            "fs": fs,
            "remote": remote,
        ])
        return response.item
    }

    /// Create a directory.
    public func mkdir(fs: String, remote: String) async throws {
        try await call("operations/mkdir", params: [
            "fs": fs,
            "remote": remote,
        ])
    }

    /// Delete a single file.
    public func deleteFile(fs: String, remote: String) async throws {
        try await call("operations/deletefile", params: [
            "fs": fs,
            "remote": remote,
        ])
    }

    /// Recursively delete a directory and its contents.
    public func purge(fs: String, remote: String) async throws {
        try await call("operations/purge", params: [
            "fs": fs,
            "remote": remote,
        ])
    }

    /// Move a file from one location to another.
    public func moveFile(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String
    ) async throws {
        try await call("operations/movefile", params: [
            "srcFs": srcFs,
            "srcRemote": srcRemote,
            "dstFs": dstFs,
            "dstRemote": dstRemote,
        ])
    }

    /// Copy a file from one location to another.
    public func copyFile(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String
    ) async throws {
        try await call("operations/copyfile", params: [
            "srcFs": srcFs,
            "srcRemote": srcRemote,
            "dstFs": dstFs,
            "dstRemote": dstRemote,
        ])
    }

    /// Get storage quota/usage information.
    public func about(fs: String) async throws -> AboutResponse {
        try await call("operations/about", params: ["fs": fs])
    }
}
```

- [ ] **Step 5: Implement Remotes.swift**

Write `RcloneKit/Sources/RcloneKit/Remotes.swift`:

```swift
import Foundation

extension RcloneClient {

    /// List all configured remote names.
    public func listRemotes() async throws -> [String] {
        let response: RemoteListResponse = try await call("config/listremotes")
        return response.remotes
    }

    /// Dump all remote configurations.
    public func configDump() async throws -> [String: [String: String]] {
        try await call("config/dump")
    }

    /// Get available cloud providers and their configuration schemas.
    public func getProviders() async throws -> [Provider] {
        let response: ProvidersResponse = try await call("config/providers")
        return response.providers
    }

    /// Create a new remote.
    public func createRemote(
        name: String,
        type: String,
        parameters: [String: String] = [:]
    ) async throws {
        var params: [String: any Sendable] = [
            "name": name,
            "type": type,
        ]
        params["parameters"] = parameters
        try await call("config/create", params: params)
    }

    /// Update an existing remote's configuration.
    public func updateRemote(
        name: String,
        parameters: [String: String]
    ) async throws {
        try await call("config/update", params: [
            "name": name,
            "parameters": parameters,
        ])
    }

    /// Delete a remote.
    public func deleteRemote(name: String) async throws {
        try await call("config/delete", params: ["name": name])
    }
}
```

- [ ] **Step 6: Implement Sync.swift**

Write `RcloneKit/Sources/RcloneKit/Sync.swift`:

```swift
import Foundation

extension RcloneClient {

    /// Start an async copy operation. Returns the job ID.
    public func copy(srcFs: String, dstFs: String) async throws -> Int {
        let response: AsyncJobResponse = try await call("sync/copy", params: [
            "srcFs": srcFs,
            "dstFs": dstFs,
            "_async": true,
        ])
        return response.jobid
    }

    /// Start an async sync operation. Returns the job ID.
    public func sync(srcFs: String, dstFs: String) async throws -> Int {
        let response: AsyncJobResponse = try await call("sync/sync", params: [
            "srcFs": srcFs,
            "dstFs": dstFs,
            "_async": true,
        ])
        return response.jobid
    }
}
```

- [ ] **Step 7: Implement Jobs.swift**

Write `RcloneKit/Sources/RcloneKit/Jobs.swift`:

```swift
import Foundation

extension RcloneClient {

    /// List all active job IDs.
    public func listJobs() async throws -> [Int] {
        let response: JobListResponse = try await call("job/list")
        return response.jobids
    }

    /// Get the status of a specific job.
    public func jobStatus(id: Int) async throws -> Job {
        try await call("job/status", params: ["jobid": id])
    }

    /// Stop a running job.
    public func stopJob(id: Int) async throws {
        try await call("job/stop", params: ["jobid": id])
    }
}
```

- [ ] **Step 8: Implement Stats.swift**

Write `RcloneKit/Sources/RcloneKit/Stats.swift`:

```swift
import Foundation

extension RcloneClient {

    /// Get current transfer statistics.
    public func getStats(group: String? = nil) async throws -> StatsResponse {
        var params: [String: any Sendable] = [:]
        if let group {
            params["group"] = group
        }
        return try await call("core/stats", params: params)
    }

    /// Set bandwidth limit. Pass empty string to remove limit.
    public func setBandwidthLimit(rate: String) async throws -> BandwidthLimitResponse {
        try await call("core/bwlimit", params: ["rate": rate])
    }

    /// Get current bandwidth limit.
    public func getBandwidthLimit() async throws -> BandwidthLimitResponse {
        try await call("core/bwlimit")
    }
}
```

- [ ] **Step 9: Run all tests**

```bash
cd /Volumes/DATA/Dev/Nimbus/RcloneKit
swift test
```

Expected: All tests pass.

- [ ] **Step 10: Commit**

```bash
git add RcloneKit/Sources/RcloneKit/Operations.swift RcloneKit/Sources/RcloneKit/Remotes.swift \
       RcloneKit/Sources/RcloneKit/Sync.swift RcloneKit/Sources/RcloneKit/Jobs.swift \
       RcloneKit/Sources/RcloneKit/Stats.swift \
       RcloneKit/Tests/RcloneKitTests/OperationsTests.swift RcloneKit/Tests/RcloneKitTests/RemotesTests.swift
git commit -m "feat(RcloneKit): add Operations, Remotes, Sync, Jobs, and Stats endpoints"
```

---

## Task 5: RcloneDaemon Service

**Files:**
- Create: `Nimbus/Nimbus/Services/RcloneDaemon.swift`

- [ ] **Step 1: Implement RcloneDaemon**

Write `Nimbus/Nimbus/Services/RcloneDaemon.swift`:

```swift
import Foundation
import Observation
import RcloneKit
import os

@Observable
@MainActor
final class RcloneDaemon {
    enum Status: Equatable {
        case idle
        case starting
        case connected
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var port: Int = 5572
    let client: RcloneClient

    private var process: Process?
    private var healthTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.nimbus.app", category: "daemon")

    private static let portRange = 5572...5580

    init() {
        client = RcloneClient()
    }

    /// Start the rclone daemon, find an available port, and wait for it to be healthy.
    func start(binaryPath: String = "/usr/local/bin/rclone") async {
        guard status != .connected && status != .starting else { return }
        status = .starting

        guard let availablePort = await Self.findAvailablePort(in: Self.portRange) else {
            status = .error("No available port in range \(Self.portRange)")
            return
        }
        port = availablePort
        await client.updatePort(availablePort)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "rcd",
            "--rc-no-auth",
            "--rc-addr", "127.0.0.1:\(availablePort)",
            "--rc-allow-origin=*",
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            process = proc
            logger.info("Started rclone on port \(availablePort), pid \(proc.processIdentifier)")
        } catch {
            status = .error("Failed to start rclone: \(error.localizedDescription)")
            return
        }

        // Poll for health
        let maxAttempts = 30
        for attempt in 1...maxAttempts {
            if await client.healthCheck() {
                status = .connected
                logger.info("Rclone healthy after \(attempt) attempts")
                return
            }
            // Check if process died
            if !proc.isRunning {
                status = .error("Rclone process exited unexpectedly")
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        status = .error("Rclone failed to respond after \(maxAttempts) health checks")
    }

    /// Stop the rclone daemon.
    func stop() {
        healthTask?.cancel()
        healthTask = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
            logger.info("Stopped rclone daemon")
        }
        process = nil
        status = .idle
    }

    /// Retry starting the daemon after an error.
    func retry(binaryPath: String = "/usr/local/bin/rclone") async {
        stop()
        await start(binaryPath: binaryPath)
    }

    private static func findAvailablePort(in range: ClosedRange<Int>) async -> Int? {
        for port in range {
            let available = await isPortAvailable(port)
            if available {
                return port
            }
        }
        return nil
    }

    private static func isPortAvailable(_ port: Int) async -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

Expected: Builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Nimbus/Nimbus/Services/RcloneDaemon.swift
git commit -m "feat: add RcloneDaemon service for rclone process lifecycle"
```

---

## Task 6: MountManager Service

**Files:**
- Create: `Nimbus/Nimbus/Services/MountManager.swift`

- [ ] **Step 1: Implement MountManager**

Write `Nimbus/Nimbus/Services/MountManager.swift`:

```swift
import Foundation
import Observation
import os

struct ActiveMount: Identifiable, Sendable {
    let id: String // mount point path
    let remote: String
    let mountPoint: String
    let port: Int
}

@Observable
@MainActor
final class MountManager {
    private(set) var activeMounts: [ActiveMount] = []
    private var nfsProcesses: [String: Process] = [:] // mountPoint → nfs server process

    private let logger = Logger(subsystem: "com.nimbus.app", category: "mount")
    private var healthTask: Task<Void, Never>?

    private static let nfsPortRange = 19049...19149

    /// Mount a remote via NFS.
    func mount(remote: String, mountPoint: String, readOnly: Bool) async throws {
        try validateMountPoint(mountPoint)
        try validateRemote(remote)

        guard let nfsPort = findAvailableNfsPort() else {
            throw MountError.noAvailablePort
        }

        // Create mount point directory if needed
        try FileManager.default.createDirectory(
            atPath: mountPoint,
            withIntermediateDirectories: true
        )

        // Spawn rclone NFS server
        let nfsProcess = Process()
        nfsProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/rclone") // TODO: configurable
        var args = ["serve", "nfs", remote, "--addr", "localhost:\(nfsPort)"]
        if readOnly {
            args.append("--read-only")
        } else {
            args.append(contentsOf: ["--vfs-cache-mode", "writes"])
        }
        nfsProcess.arguments = args
        nfsProcess.standardOutput = FileHandle.nullDevice
        nfsProcess.standardError = FileHandle.nullDevice

        try nfsProcess.run()
        logger.info("Spawned NFS server for \(remote) on port \(nfsPort)")

        // Wait for NFS server to be ready (up to 10 seconds)
        let ready = await waitForServerReady(port: nfsPort, timeout: 10.0)
        if !ready {
            nfsProcess.terminate()
            throw MountError.serverStartTimeout
        }

        // Mount via mount_nfs
        let mountProcess = Process()
        mountProcess.executableURL = URL(fileURLWithPath: "/sbin/mount_nfs")
        mountProcess.arguments = [
            "-o", "nfsvers=3,tcp,nolocks,noresvport,soft,timeo=50,nobrowse,nosuid,nodev,port=\(nfsPort),mountport=\(nfsPort)",
            "localhost:/",
            mountPoint,
        ]

        let pipe = Pipe()
        mountProcess.standardError = pipe
        mountProcess.standardOutput = FileHandle.nullDevice

        try mountProcess.run()
        mountProcess.waitUntilExit()

        if mountProcess.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "unknown error"
            nfsProcess.terminate()
            throw MountError.mountFailed(errorMessage)
        }

        let mount = ActiveMount(
            id: mountPoint,
            remote: remote,
            mountPoint: mountPoint,
            port: nfsPort
        )
        activeMounts.append(mount)
        nfsProcesses[mountPoint] = nfsProcess
        logger.info("Mounted \(remote) at \(mountPoint)")
    }

    /// Unmount a remote.
    func unmount(mountPoint: String) async throws {
        // Run umount with timeout
        let umountProcess = Process()
        umountProcess.executableURL = URL(fileURLWithPath: "/sbin/umount")
        umountProcess.arguments = [mountPoint]
        umountProcess.standardOutput = FileHandle.nullDevice
        umountProcess.standardError = FileHandle.nullDevice

        try umountProcess.run()

        // Wait up to 5 seconds
        let completed = await waitForProcess(umountProcess, timeout: 5.0)
        if !completed || umountProcess.terminationStatus != 0 {
            // Force unmount
            logger.warning("umount timed out, force unmounting \(mountPoint)")
            let forceProcess = Process()
            forceProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            forceProcess.arguments = ["unmount", "force", mountPoint]
            forceProcess.standardOutput = FileHandle.nullDevice
            forceProcess.standardError = FileHandle.nullDevice
            try forceProcess.run()
            forceProcess.waitUntilExit()
        }

        // Kill NFS server
        if let nfsProcess = nfsProcesses[mountPoint] {
            if nfsProcess.isRunning {
                nfsProcess.terminate()
                nfsProcess.waitUntilExit()
            }
            nfsProcesses.removeValue(forKey: mountPoint)
        }

        activeMounts.removeAll { $0.mountPoint == mountPoint }
        logger.info("Unmounted \(mountPoint)")
    }

    /// Start background health monitoring.
    func startHealthMonitor() {
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await self?.checkHealth()
            }
        }
    }

    /// Stop health monitoring and clean up all mounts.
    func stopAll() async {
        healthTask?.cancel()
        healthTask = nil

        for mount in activeMounts {
            try? await unmount(mountPoint: mount.mountPoint)
        }
    }

    /// Clean up stale mounts from a previous session.
    func cleanupStaleMounts() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Find stale localhost NFS mounts
            for line in output.split(separator: "\n") {
                let lineStr = String(line)
                if lineStr.contains("localhost") && lineStr.contains("nfs") {
                    // Extract mount point: "X on /path/to/mount (nfs, ...)"
                    if let onRange = lineStr.range(of: " on "),
                       let parenRange = lineStr.range(of: " (", range: onRange.upperBound..<lineStr.endIndex) {
                        let mountPoint = String(lineStr[onRange.upperBound..<parenRange.lowerBound])
                        logger.info("Cleaning stale mount: \(mountPoint)")
                        let forceProcess = Process()
                        forceProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                        forceProcess.arguments = ["unmount", "force", mountPoint]
                        forceProcess.standardOutput = FileHandle.nullDevice
                        forceProcess.standardError = FileHandle.nullDevice
                        try? forceProcess.run()
                        forceProcess.waitUntilExit()
                    }
                }
            }
        } catch {
            logger.error("Failed to check for stale mounts: \(error)")
        }
    }

    // MARK: - Private

    private func checkHealth() {
        var deadMounts: [String] = []

        for (mountPoint, process) in nfsProcesses {
            if !process.isRunning {
                logger.warning("NFS server for \(mountPoint) died")
                deadMounts.append(mountPoint)
            }
        }

        for mountPoint in deadMounts {
            nfsProcesses.removeValue(forKey: mountPoint)
            activeMounts.removeAll { $0.mountPoint == mountPoint }

            // Best-effort force unmount
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            proc.arguments = ["unmount", "force", mountPoint]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    private func validateMountPoint(_ path: String) throws {
        guard path.hasPrefix("/") else {
            throw MountError.invalidMountPoint("Must be an absolute path")
        }
        guard !path.contains("..") else {
            throw MountError.invalidMountPoint("Must not contain '..'")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else {
            throw MountError.invalidMountPoint("Must be under home directory")
        }
    }

    private func validateRemote(_ remote: String) throws {
        let pattern = /^[\w\s-]+:.*$/
        guard remote.wholeMatch(of: pattern) != nil else {
            throw MountError.invalidRemote("Invalid remote format: \(remote)")
        }
    }

    private func findAvailableNfsPort() -> Int? {
        let usedPorts = Set(activeMounts.map(\.port))
        for port in Self.nfsPortRange {
            if !usedPorts.contains(port) {
                return port
            }
        }
        return nil
    }

    private func waitForServerReady(port: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let socketFD = socket(AF_INET, SOCK_STREAM, 0)
            guard socketFD >= 0 else {
                try? await Task.sleep(for: .milliseconds(200))
                continue
            }
            defer { close(socketFD) }

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if result == 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private func waitForProcess(_ process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && process.isRunning {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return !process.isRunning
    }
}

enum MountError: Error, LocalizedError {
    case invalidMountPoint(String)
    case invalidRemote(String)
    case noAvailablePort
    case serverStartTimeout
    case mountFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMountPoint(let msg): "Invalid mount point: \(msg)"
        case .invalidRemote(let msg): "Invalid remote: \(msg)"
        case .noAvailablePort: "No available NFS port"
        case .serverStartTimeout: "NFS server failed to start within timeout"
        case .mountFailed(let msg): "Mount failed: \(msg)"
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 3: Commit**

```bash
git add Nimbus/Nimbus/Services/MountManager.swift
git commit -m "feat: add MountManager service for NFS mount lifecycle"
```

---

## Task 7: FileProviderBridge Service

**Files:**
- Create: `Nimbus/Nimbus/Services/FileProviderBridge.swift`

- [ ] **Step 1: Implement FileProviderBridge**

Write `Nimbus/Nimbus/Services/FileProviderBridge.swift`:

```swift
import FileProvider
import Foundation
import os

@MainActor
final class FileProviderBridge {
    private let logger = Logger(subsystem: "com.nimbus.app", category: "fileprovider")
    private static let appGroupID = "group.com.nimbus.app"

    /// Register a File Provider domain for a remote.
    func addDomain(identifier: String, displayName: String) async throws {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: identifier),
            displayName: displayName
        )

        // Remove existing domain first (update pattern)
        let existing = try await NSFileProviderManager.domains()
        if existing.contains(where: { $0.identifier.rawValue == identifier }) {
            try await NSFileProviderManager.remove(domain)
        }

        try await NSFileProviderManager.add(domain)
        logger.info("Added File Provider domain: \(identifier)")
    }

    /// Remove a File Provider domain.
    func removeDomain(identifier: String) async throws {
        let domains = try await NSFileProviderManager.domains()
        guard let domain = domains.first(where: { $0.identifier.rawValue == identifier }) else {
            logger.warning("Domain not found for removal: \(identifier)")
            return
        }
        try await NSFileProviderManager.remove(domain)
        logger.info("Removed File Provider domain: \(identifier)")
    }

    /// List all registered File Provider domains.
    func listDomains() async throws -> [(identifier: String, displayName: String)] {
        let domains = try await NSFileProviderManager.domains()
        return domains.map { ($0.identifier.rawValue, $0.displayName) }
    }

    /// Sync rclone port and remote list to app group for the extension to read.
    func syncState(remotes: [String], port: Int) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            logger.error("Failed to access app group UserDefaults")
            return
        }
        defaults.set(port, forKey: "rclonePort")
        defaults.set(remotes, forKey: "remotes")
        defaults.set(Date().timeIntervalSince1970, forKey: "updatedAt")
        logger.info("Synced state: port=\(port), remotes=\(remotes)")
    }

    /// Remove domains that don't correspond to active remotes.
    func cleanupStaleDomains(activeRemotes: [String]) async -> [String] {
        var removed: [String] = []
        do {
            let domains = try await NSFileProviderManager.domains()
            for domain in domains {
                let id = domain.identifier.rawValue
                if !activeRemotes.contains(id) {
                    do {
                        try await NSFileProviderManager.remove(domain)
                        removed.append(id)
                        logger.info("Cleaned up stale domain: \(id)")
                    } catch {
                        logger.warning("Failed to remove stale domain \(id): \(error)")
                    }
                }
            }
        } catch {
            logger.error("Failed to list domains for cleanup: \(error)")
        }
        return removed
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 3: Commit**

```bash
git add Nimbus/Nimbus/Services/FileProviderBridge.swift
git commit -m "feat: add FileProviderBridge for direct NSFileProviderManager domain management"
```

---

## Task 8: App State (AppSettings + MountConfiguration + TransferStore)

**Files:**
- Create: `Nimbus/Nimbus/State/AppSettings.swift`
- Create: `Nimbus/Nimbus/State/MountConfiguration.swift`
- Create: `Nimbus/Nimbus/State/TransferStore.swift`

- [ ] **Step 1: Implement AppSettings**

Write `Nimbus/Nimbus/State/AppSettings.swift`:

```swift
import SwiftUI

enum Appearance: String, CaseIterable {
    case light, dark, system
}

@Observable
final class AppSettings {
    @AppStorage("rclonePort") var rclonePort: Int = 5572
    @AppStorage("rcloneBinaryPath") var rcloneBinaryPath: String = "/usr/local/bin/rclone"
    @AppStorage("bandwidthLimit") var bandwidthLimit: String = ""
    @AppStorage("concurrentTransfers") var concurrentTransfers: Int = 4
    @AppStorage("onboardingComplete") var onboardingComplete: Bool = false
    @AppStorage("appearance") var appearance: Appearance = .system
    @AppStorage("sidebarCollapsed") var sidebarCollapsed: Bool = false

    var colorScheme: ColorScheme? {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

extension Appearance: RawRepresentable {
    // Already RawRepresentable via String
}
```

- [ ] **Step 2: Implement MountConfiguration**

Write `Nimbus/Nimbus/State/MountConfiguration.swift`:

```swift
import Foundation
import Observation

enum VFSMode: String, Codable, CaseIterable {
    case readOnly = "read-only"
    case readWrite = "read-write"
}

enum MountBackend: String, Codable, CaseIterable {
    case nfs
    case fileProvider = "fileprovider"
}

struct MountConfig: Codable, Identifiable {
    var id: String { "\(remote)-\(mountPoint)" }
    let remote: String
    let mountPoint: String
    var vfsMode: VFSMode
    var autoMount: Bool
    var backend: MountBackend
}

@Observable
final class MountConfigStore {
    private(set) var configs: [MountConfig] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let nimbus = appSupport.appendingPathComponent("Nimbus", isDirectory: true)
        try? FileManager.default.createDirectory(at: nimbus, withIntermediateDirectories: true)
        fileURL = nimbus.appendingPathComponent("mount-configs.json")
        load()
    }

    func addConfig(_ config: MountConfig) {
        configs.append(config)
        save()
    }

    func removeConfig(id: String) {
        configs.removeAll { $0.id == id }
        save()
    }

    func toggleAutoMount(id: String) {
        if let index = configs.firstIndex(where: { $0.id == id }) {
            configs[index].autoMount.toggle()
            save()
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            configs = try JSONDecoder().decode([MountConfig].self, from: data)
        } catch {
            configs = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Log but don't crash
        }
    }
}
```

- [ ] **Step 3: Implement TransferStore**

Write `Nimbus/Nimbus/State/TransferStore.swift`:

```swift
import Foundation
import Observation
import RcloneKit

enum TransferOperation: String {
    case copy, sync
}

enum TransferStatus {
    case active
    case completed
    case failed(String)
    case cancelled
}

struct Transfer: Identifiable {
    let id: Int // job ID
    let operation: TransferOperation
    let srcFs: String
    let dstFs: String
    let startedAt: Date
    var completedAt: Date?
    var status: TransferStatus
}

@Observable
@MainActor
final class TransferStore {
    private(set) var transfers: [Transfer] = []
    private var pollingTask: Task<Void, Never>?

    var activeTransfers: [Transfer] {
        transfers.filter {
            if case .active = $0.status { return true }
            return false
        }
    }

    var completedTransfers: [Transfer] {
        transfers.filter {
            switch $0.status {
            case .completed, .failed, .cancelled: return true
            case .active: return false
            }
        }
    }

    func addTransfer(jobId: Int, operation: TransferOperation, srcFs: String, dstFs: String) {
        let transfer = Transfer(
            id: jobId,
            operation: operation,
            srcFs: srcFs,
            dstFs: dstFs,
            startedAt: Date(),
            status: .active
        )
        transfers.append(transfer)
    }

    func completeTransfer(jobId: Int) {
        if let index = transfers.firstIndex(where: { $0.id == jobId }) {
            transfers[index].status = .completed
            transfers[index].completedAt = Date()
        }
    }

    func failTransfer(jobId: Int, error: String) {
        if let index = transfers.firstIndex(where: { $0.id == jobId }) {
            transfers[index].status = .failed(error)
            transfers[index].completedAt = Date()
        }
    }

    func cancelTransfer(jobId: Int) {
        if let index = transfers.firstIndex(where: { $0.id == jobId }) {
            transfers[index].status = .cancelled
            transfers[index].completedAt = Date()
        }
    }

    func clearCompleted() {
        transfers.removeAll {
            switch $0.status {
            case .completed, .failed, .cancelled: return true
            case .active: return false
            }
        }
    }

    /// Start polling active jobs for completion.
    func startPolling(client: RcloneClient) {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.pollActiveJobs(client: client)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func pollActiveJobs(client: RcloneClient) async {
        for transfer in activeTransfers {
            do {
                let job = try await client.jobStatus(id: transfer.id)
                if job.finished {
                    if job.success {
                        completeTransfer(jobId: transfer.id)
                    } else {
                        failTransfer(jobId: transfer.id, error: job.error)
                    }
                }
            } catch {
                // Transient error — keep polling
            }
        }
    }
}
```

- [ ] **Step 4: Build to verify compilation**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 5: Commit**

```bash
git add Nimbus/Nimbus/State/AppSettings.swift Nimbus/Nimbus/State/MountConfiguration.swift \
       Nimbus/Nimbus/State/TransferStore.swift
git commit -m "feat: add AppSettings, MountConfigStore, and TransferStore state management"
```

---

## Task 9: App Shell (NimbusApp + Sidebar + ContentView)

**Files:**
- Modify: `Nimbus/Nimbus/NimbusApp.swift`
- Create: `Nimbus/Nimbus/Views/Sidebar.swift`
- Create: `Nimbus/Nimbus/Views/ContentView.swift`

- [ ] **Step 1: Implement Sidebar**

Write `Nimbus/Nimbus/Views/Sidebar.swift`:

```swift
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case remotes = "Remotes"
    case mounts = "Mounts"
    case transfers = "Transfers"
    case copySync = "Copy / Sync"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .remotes: "cloud"
        case .mounts: "externaldrive"
        case .transfers: "arrow.up.arrow.down"
        case .copySync: "doc.on.doc"
        case .settings: "gear"
        }
    }
}

struct Sidebar: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("Nimbus")
    }
}
```

- [ ] **Step 2: Implement ContentView**

Write `Nimbus/Nimbus/Views/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .remotes
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon

    var body: some View {
        if !settings.onboardingComplete {
            OnboardingView()
        } else {
            NavigationSplitView {
                Sidebar(selection: $selection)
                    .frame(minWidth: 180)
            } detail: {
                detailView
            }
            .frame(minWidth: 800, minHeight: 600)
            .toolbar {
                if case .error(let message) = daemon.status {
                    ToolbarItem(placement: .status) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .remotes:
            RemotesView()
        case .mounts:
            MountsView()
        case .transfers:
            TransfersView()
        case .copySync:
            CopySyncView()
        case .settings:
            SettingsView()
        case nil:
            Text("Select an item from the sidebar")
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Update NimbusApp.swift with service initialization**

Replace `Nimbus/Nimbus/NimbusApp.swift`:

```swift
import SwiftUI

@main
struct NimbusApp: App {
    @State private var daemon = RcloneDaemon()
    @State private var mountManager = MountManager()
    @State private var fileProviderBridge = FileProviderBridge()
    @State private var settings = AppSettings()
    @State private var mountConfigs = MountConfigStore()
    @State private var transferStore = TransferStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(daemon)
                .environment(mountManager)
                .environment(fileProviderBridge)
                .environment(settings)
                .environment(mountConfigs)
                .environment(transferStore)
                .preferredColorScheme(settings.colorScheme)
                .task {
                    await startApp()
                }
        }
        .defaultSize(width: 1000, height: 700)

        MenuBarExtra("Nimbus", systemImage: "cloud") {
            Button("Show Nimbus") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("Quit") {
                Task {
                    await shutdown()
                    NSApp.terminate(nil)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(daemon)
        }
    }

    private func startApp() async {
        // Clean up stale mounts from previous sessions
        await mountManager.cleanupStaleMounts()

        // Start rclone daemon
        await daemon.start(binaryPath: settings.rcloneBinaryPath)

        if daemon.status == .connected {
            // Start transfer polling
            transferStore.startPolling(client: daemon.client)

            // Start mount health monitor
            mountManager.startHealthMonitor()

            // Auto-mount saved configs
            for config in mountConfigs.configs where config.autoMount {
                if config.backend == .nfs {
                    try? await mountManager.mount(
                        remote: config.remote,
                        mountPoint: config.mountPoint,
                        readOnly: config.vfsMode == .readOnly
                    )
                }
            }
        }
    }

    private func shutdown() async {
        transferStore.stopPolling()
        await mountManager.stopAll()
        daemon.stop()
    }
}
```

- [ ] **Step 4: Create placeholder views for compilation**

These will be replaced in later tasks. Create stub files:

Write `Nimbus/Nimbus/Views/Remotes/RemotesView.swift`:
```swift
import SwiftUI

struct RemotesView: View {
    var body: some View {
        Text("Remotes")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Write `Nimbus/Nimbus/Views/Mounts/MountsView.swift`:
```swift
import SwiftUI

struct MountsView: View {
    var body: some View {
        Text("Mounts")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Write `Nimbus/Nimbus/Views/Transfers/TransfersView.swift`:
```swift
import SwiftUI

struct TransfersView: View {
    var body: some View {
        Text("Transfers")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Write `Nimbus/Nimbus/Views/CopySync/CopySyncView.swift`:
```swift
import SwiftUI

struct CopySyncView: View {
    var body: some View {
        Text("Copy / Sync")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Write `Nimbus/Nimbus/Views/Settings/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Text("Settings")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Write `Nimbus/Nimbus/Views/Onboarding/OnboardingView.swift`:
```swift
import SwiftUI

struct OnboardingView: View {
    var body: some View {
        Text("Onboarding")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Build and run**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

Expected: App builds. Navigation works with sidebar → placeholder views.

- [ ] **Step 6: Commit**

```bash
git add Nimbus/Nimbus/
git commit -m "feat: add app shell with NavigationSplitView, sidebar, MenuBarExtra, and service lifecycle"
```

---

## Task 10: Settings & Onboarding Views

**Files:**
- Modify: `Nimbus/Nimbus/Views/Settings/SettingsView.swift`
- Create: `Nimbus/Nimbus/Views/Settings/AppearanceSection.swift`
- Create: `Nimbus/Nimbus/Views/Settings/TransferSection.swift`
- Create: `Nimbus/Nimbus/Views/Settings/RcloneSection.swift`
- Create: `Nimbus/Nimbus/Views/Settings/AboutSection.swift`
- Modify: `Nimbus/Nimbus/Views/Onboarding/OnboardingView.swift`

- [ ] **Step 1: Implement Settings sections**

Write `Nimbus/Nimbus/Views/Settings/AppearanceSection.swift`:

```swift
import SwiftUI

struct AppearanceSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(Appearance.allCases, id: \.self) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
```

Write `Nimbus/Nimbus/Views/Settings/TransferSection.swift`:

```swift
import SwiftUI

struct TransferSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            TextField("Bandwidth Limit", text: $settings.bandwidthLimit, prompt: Text("e.g., 10M (empty for unlimited)"))
            Stepper("Concurrent Transfers: \(settings.concurrentTransfers)", value: $settings.concurrentTransfers, in: 1...20)
        }
    }
}
```

Write `Nimbus/Nimbus/Views/Settings/RcloneSection.swift`:

```swift
import SwiftUI

struct RcloneSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon

    var body: some View {
        @Bindable var settings = settings

        Form {
            TextField("Rclone Binary Path", text: $settings.rcloneBinaryPath)
            LabeledContent("Daemon Port") {
                Text("\(daemon.port)")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Daemon Status") {
                switch daemon.status {
                case .idle:
                    Text("Not running").foregroundStyle(.secondary)
                case .starting:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Starting...")
                    }
                case .connected:
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .error(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
```

Write `Nimbus/Nimbus/Views/Settings/AboutSection.swift`:

```swift
import SwiftUI

struct AboutSection: View {
    var body: some View {
        Form {
            LabeledContent("Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
            }
            LabeledContent("Build") {
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
            }
        }
    }
}
```

- [ ] **Step 2: Implement SettingsView with tabs**

Replace `Nimbus/Nimbus/Views/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSection()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            TransferSection()
                .tabItem { Label("Transfers", systemImage: "arrow.up.arrow.down") }

            RcloneSection()
                .tabItem { Label("Rclone", systemImage: "terminal") }

            AboutSection()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 250)
        .padding()
    }
}
```

- [ ] **Step 3: Implement OnboardingView**

Replace `Nimbus/Nimbus/Views/Onboarding/OnboardingView.swift`:

```swift
import SwiftUI
import RcloneKit

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @State private var remotes: [String] = []
    @State private var showAddRemote = false
    @State private var loadingRemotes = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cloud")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to Nimbus")
                .font(.largeTitle.bold())

            Text("Your cloud storage, managed natively.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            // Step 1: Daemon status
            GroupBox {
                HStack {
                    statusIcon
                    VStack(alignment: .leading) {
                        Text("Rclone Daemon")
                            .font(.headline)
                        Text(daemonStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Step 2: Remotes
            if daemon.status == .connected {
                GroupBox {
                    HStack {
                        if remotes.isEmpty {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        VStack(alignment: .leading) {
                            Text("Cloud Remotes")
                                .font(.headline)
                            if remotes.isEmpty {
                                Text("Add at least one cloud remote to get started.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(remotes.count) remote(s) configured")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if remotes.isEmpty {
                            Button("Add Remote") {
                                showAddRemote = true
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer()

            HStack {
                Button("Skip for Now") {
                    settings.onboardingComplete = true
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Get Started") {
                    settings.onboardingComplete = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(remotes.isEmpty && daemon.status == .connected)
            }
        }
        .frame(width: 500, height: 500)
        .padding(40)
        .task {
            if daemon.status == .connected {
                await loadRemotes()
            }
        }
        .onChange(of: daemon.status) {
            if daemon.status == .connected {
                Task { await loadRemotes() }
            }
        }
        .sheet(isPresented: $showAddRemote) {
            AddRemoteSheet(onComplete: {
                Task { await loadRemotes() }
            })
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch daemon.status {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .starting:
            ProgressView().controlSize(.small)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    private var daemonStatusText: String {
        switch daemon.status {
        case .idle: "Not started"
        case .starting: "Connecting..."
        case .connected: "Connected on port \(daemon.port)"
        case .error(let msg): msg
        }
    }

    private func loadRemotes() async {
        loadingRemotes = true
        defer { loadingRemotes = false }
        do {
            remotes = try await daemon.client.listRemotes()
        } catch {
            remotes = []
        }
    }
}
```

- [ ] **Step 4: Build**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

Expected: Builds (AddRemoteSheet referenced in onboarding won't exist yet — temporarily comment it out or add a stub).

- [ ] **Step 5: Commit**

```bash
git add Nimbus/Nimbus/Views/Settings/ Nimbus/Nimbus/Views/Onboarding/
git commit -m "feat: add Settings tabs and Onboarding wizard views"
```

---

## Task 11: Remotes Management Views + ViewModel

**Files:**
- Create: `Nimbus/Nimbus/ViewModels/RemotesViewModel.swift`
- Modify: `Nimbus/Nimbus/Views/Remotes/RemotesView.swift`
- Create: `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift`
- Create: `Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift`
- Create: `Nimbus/Nimbus/Views/Remotes/EditRemoteSheet.swift`
- Create: `Nimbus/Nimbus/Views/Remotes/ConfigForm.swift`

- [ ] **Step 1: Implement RemotesViewModel**

Write `Nimbus/Nimbus/ViewModels/RemotesViewModel.swift`:

```swift
import Foundation
import Observation
import RcloneKit

@Observable
@MainActor
final class RemotesViewModel {
    private(set) var remotes: [Remote] = []
    private(set) var providers: [Provider] = []
    private(set) var isLoading = false
    private(set) var error: String?

    private let client: RcloneClient

    init(client: RcloneClient) {
        self.client = client
    }

    func loadRemotes() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let names = client.listRemotes()
            async let dump = client.configDump()
            let (remoteNames, configs) = try await (names, dump)

            remotes = remoteNames.map { name in
                let config = configs[name] ?? [:]
                return Remote(
                    name: name,
                    type: config["type"] ?? "unknown",
                    config: config
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadProviders() async {
        do {
            providers = try await client.getProviders()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteRemote(name: String) async {
        do {
            try await client.deleteRemote(name: name)
            remotes.removeAll { $0.name == name }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createRemote(name: String, type: String, parameters: [String: String]) async throws {
        try await client.createRemote(name: name, type: type, parameters: parameters)
        await loadRemotes()
    }

    func updateRemote(name: String, parameters: [String: String]) async throws {
        try await client.updateRemote(name: name, parameters: parameters)
        await loadRemotes()
    }
}
```

- [ ] **Step 2: Implement ConfigForm (dynamic provider form)**

Write `Nimbus/Nimbus/Views/Remotes/ConfigForm.swift`:

```swift
import SwiftUI
import RcloneKit

struct ConfigForm: View {
    let options: [ProviderOption]
    @Binding var values: [String: String]
    @State private var showAdvanced = false

    var body: some View {
        let required = options.filter { $0.required && !$0.advanced }
        let basic = options.filter { !$0.required && !$0.advanced }
        let advanced = options.filter { $0.advanced }

        Form {
            if !required.isEmpty {
                Section("Required") {
                    ForEach(required) { option in
                        optionField(option)
                    }
                }
            }

            if !basic.isEmpty {
                Section("Optional") {
                    ForEach(basic) { option in
                        optionField(option)
                    }
                }
            }

            if !advanced.isEmpty {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    ForEach(advanced) { option in
                        optionField(option)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func optionField(_ option: ProviderOption) -> some View {
        let binding = Binding<String>(
            get: { values[option.name] ?? option.defaultValue },
            set: { values[option.name] = $0 }
        )

        VStack(alignment: .leading, spacing: 4) {
            if option.isPassword {
                SecureField(option.name, text: binding, prompt: Text(option.help))
            } else if option.type == "bool" {
                Toggle(option.name, isOn: Binding<Bool>(
                    get: { (values[option.name] ?? option.defaultValue) == "true" },
                    set: { values[option.name] = String($0) }
                ))
            } else if let examples = option.examples, !examples.isEmpty {
                Picker(option.name, selection: binding) {
                    Text("Default").tag("")
                    ForEach(examples, id: \.value) { example in
                        Text("\(example.value) — \(example.help)").tag(example.value)
                    }
                }
            } else {
                TextField(option.name, text: binding, prompt: Text(option.help))
            }

            if !option.help.isEmpty {
                Text(option.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
```

- [ ] **Step 3: Implement AddRemoteSheet**

Write `Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift`:

```swift
import SwiftUI
import RcloneKit

struct AddRemoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RcloneDaemon.self) private var daemon
    @State private var name = ""
    @State private var selectedProvider: Provider?
    @State private var providers: [Provider] = []
    @State private var values: [String: String] = [:]
    @State private var isSaving = false
    @State private var error: String?
    @State private var searchText = ""

    var onComplete: (() -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if selectedProvider == nil {
                    providerPicker
                } else {
                    configEditor
                }
            }
            .navigationTitle(selectedProvider == nil ? "Select Provider" : "Configure \(selectedProvider!.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if selectedProvider != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(name.isEmpty || isSaving)
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            do {
                providers = try await daemon.client.getProviders()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private var filteredProviders: [Provider] {
        if searchText.isEmpty { return providers }
        return providers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var providerPicker: some View {
        List(filteredProviders, id: \.name, selection: Binding<String?>(
            get: { selectedProvider?.name },
            set: { name in
                if let name, let provider = providers.first(where: { $0.name == name }) {
                    selectedProvider = provider
                }
            }
        )) { provider in
            VStack(alignment: .leading) {
                Text(provider.name)
                    .font(.headline)
                Text(provider.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .tag(provider.name)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedProvider = provider
            }
        }
        .searchable(text: $searchText, prompt: "Search providers")
    }

    private var configEditor: some View {
        VStack {
            Form {
                TextField("Remote Name", text: $name, prompt: Text("e.g., my-s3"))

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            if let provider = selectedProvider {
                ConfigForm(options: provider.options, values: $values)
            }
        }
    }

    private func save() async {
        guard let provider = selectedProvider else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }

        do {
            // Filter out empty values
            let params = values.filter { !$0.value.isEmpty }
            try await daemon.client.createRemote(name: name, type: provider.name, parameters: params)
            onComplete?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Implement EditRemoteSheet**

Write `Nimbus/Nimbus/Views/Remotes/EditRemoteSheet.swift`:

```swift
import SwiftUI
import RcloneKit

struct EditRemoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RcloneDaemon.self) private var daemon
    let remote: Remote
    @State private var values: [String: String] = [:]
    @State private var providers: [Provider] = []
    @State private var isSaving = false
    @State private var error: String?

    var onComplete: (() -> Void)?

    private var provider: Provider? {
        providers.first { $0.name == remote.type }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if let error {
                    Text(error).foregroundStyle(.red).padding()
                }

                if let provider {
                    ConfigForm(options: provider.options, values: $values)
                } else {
                    ProgressView("Loading...")
                }
            }
            .navigationTitle("Edit \(remote.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            values = remote.config
            do {
                providers = try await daemon.client.getProviders()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let params = values.filter { !$0.value.isEmpty }
            try await daemon.client.updateRemote(name: remote.name, parameters: params)
            onComplete?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

- [ ] **Step 5: Implement RemoteRow and RemotesView**

Write `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift`:

```swift
import SwiftUI
import RcloneKit

struct RemoteRow: View {
    let remote: Remote
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onBrowse: () -> Void

    var body: some View {
        HStack {
            Image(systemName: iconName(for: remote.type))
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading) {
                Text(remote.name)
                    .font(.headline)
                Text(remote.type)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Browse", systemImage: "folder") {
                onBrowse()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Browse") { onBrowse() }
            Button("Edit") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "drive": "cloud"
        case "s3": "shippingbox"
        case "dropbox": "drop"
        case "onedrive": "cloud"
        case "sftp", "ftp": "server.rack"
        case "local": "folder"
        default: "cloud"
        }
    }
}
```

Replace `Nimbus/Nimbus/Views/Remotes/RemotesView.swift`:

```swift
import SwiftUI
import RcloneKit

struct RemotesView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @State private var viewModel: RemotesViewModel?
    @State private var showAddRemote = false
    @State private var editingRemote: Remote?
    @State private var deletingRemote: Remote?
    @State private var browsingRemote: Remote?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading && viewModel.remotes.isEmpty {
                    ProgressView("Loading remotes...")
                } else if viewModel.remotes.isEmpty {
                    ContentUnavailableView(
                        "No Remotes",
                        systemImage: "cloud",
                        description: Text("Add a cloud remote to get started.")
                    )
                } else {
                    List(viewModel.remotes, id: \.name) { remote in
                        RemoteRow(
                            remote: remote,
                            onEdit: { editingRemote = remote },
                            onDelete: { deletingRemote = remote },
                            onBrowse: { browsingRemote = remote }
                        )
                    }
                }
            }
        }
        .navigationTitle("Remotes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Remote", systemImage: "plus") {
                    showAddRemote = true
                }
            }
        }
        .task {
            let vm = RemotesViewModel(client: daemon.client)
            viewModel = vm
            await vm.loadRemotes()
        }
        .sheet(isPresented: $showAddRemote) {
            AddRemoteSheet(onComplete: {
                Task { await viewModel?.loadRemotes() }
            })
        }
        .sheet(item: $editingRemote, id: \.name) { remote in
            EditRemoteSheet(remote: remote, onComplete: {
                Task { await viewModel?.loadRemotes() }
            })
        }
        .confirmationDialog(
            "Delete \(deletingRemote?.name ?? "")?",
            isPresented: Binding(
                get: { deletingRemote != nil },
                set: { if !$0 { deletingRemote = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let remote = deletingRemote {
                    Task { await viewModel?.deleteRemote(name: remote.name) }
                }
            }
        } message: {
            Text("This will remove the remote configuration. Files on the cloud are not affected.")
        }
    }
}
```

- [ ] **Step 6: Build**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 7: Commit**

```bash
git add Nimbus/Nimbus/ViewModels/RemotesViewModel.swift Nimbus/Nimbus/Views/Remotes/
git commit -m "feat: add Remotes views with provider picker, dynamic config form, CRUD"
```

---

## Task 12: File Browser Views + ViewModel

**Files:**
- Create: `Nimbus/Nimbus/ViewModels/BrowserViewModel.swift`
- Modify: `Nimbus/Nimbus/Views/Browser/BrowserView.swift` (replace stub)
- Create: `Nimbus/Nimbus/Views/Browser/FileTable.swift`
- Create: `Nimbus/Nimbus/Views/Browser/FileGrid.swift`
- Create: `Nimbus/Nimbus/Views/Browser/BrowserToolbar.swift`
- Create: `Nimbus/Nimbus/Views/Browser/FileContextMenu.swift`

- [ ] **Step 1: Implement BrowserViewModel**

Write `Nimbus/Nimbus/ViewModels/BrowserViewModel.swift`:

```swift
import Foundation
import Observation
import RcloneKit

enum ViewMode: String {
    case list, grid
}

enum SortField: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case modified = "Modified"
}

@Observable
@MainActor
final class BrowserViewModel {
    private(set) var files: [FileItem] = []
    private(set) var isLoading = false
    private(set) var error: String?

    var remote: String = ""
    var path: String = ""
    var viewMode: ViewMode = .list
    var sortField: SortField = .name
    var sortAscending: Bool = true
    var selection: Set<String> = [] // Set of Path values

    // Navigation stack for back/forward
    private(set) var pathHistory: [String] = [""]
    private(set) var historyIndex: Int = 0

    private let client: RcloneClient
    // Cache: (remote, path) → files
    private var cache: [String: [FileItem]] = [:]

    init(client: RcloneClient) {
        self.client = client
    }

    var sortedFiles: [FileItem] {
        let sorted = files.sorted { a, b in
            // Directories first
            if a.isDir != b.isDir { return a.isDir }

            switch sortField {
            case .name:
                return sortAscending
                    ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .size:
                return sortAscending ? a.size < b.size : a.size > b.size
            case .modified:
                let aTime = a.modTime ?? .distantPast
                let bTime = b.modTime ?? .distantPast
                return sortAscending ? aTime < bTime : aTime > bTime
            }
        }
        return sorted
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < pathHistory.count - 1 }

    var pathComponents: [(name: String, path: String)] {
        var components: [(String, String)] = [("\(remote):", "")]
        let parts = path.split(separator: "/")
        var accumulated = ""
        for part in parts {
            accumulated += (accumulated.isEmpty ? "" : "/") + part
            components.append((String(part), accumulated))
        }
        return components
    }

    var fs: String { "\(remote):" }

    func loadFiles() async {
        let cacheKey = "\(remote):\(path)"
        if let cached = cache[cacheKey] {
            files = cached
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let result = try await client.listFiles(fs: fs, remote: path)
            files = result
            cache[cacheKey] = result
        } catch {
            self.error = error.localizedDescription
        }
    }

    func navigateTo(path newPath: String) async {
        selection = []
        path = newPath

        // Trim forward history
        if historyIndex < pathHistory.count - 1 {
            pathHistory = Array(pathHistory[0...historyIndex])
        }
        pathHistory.append(newPath)
        historyIndex = pathHistory.count - 1

        await loadFiles()
    }

    func goBack() async {
        guard canGoBack else { return }
        historyIndex -= 1
        path = pathHistory[historyIndex]
        selection = []
        await loadFiles()
    }

    func goForward() async {
        guard canGoForward else { return }
        historyIndex += 1
        path = pathHistory[historyIndex]
        selection = []
        await loadFiles()
    }

    func createFolder(name: String) async throws {
        let folderPath = path.isEmpty ? name : "\(path)/\(name)"
        try await client.mkdir(fs: fs, remote: folderPath)
        await loadFiles()
    }

    func deleteItems(paths: [String]) async throws {
        for itemPath in paths {
            if let file = files.first(where: { $0.path == itemPath }) {
                if file.isDir {
                    try await client.purge(fs: fs, remote: itemPath)
                } else {
                    try await client.deleteFile(fs: fs, remote: itemPath)
                }
            }
        }
        selection = []
        await loadFiles()
    }

    func renameItem(oldPath: String, newName: String) async throws {
        let parentPath = oldPath.contains("/")
            ? String(oldPath[oldPath.startIndex..<oldPath.lastIndex(of: "/")!])
            : ""
        let newPath = parentPath.isEmpty ? newName : "\(parentPath)/\(newName)"
        try await client.moveFile(
            srcFs: fs, srcRemote: oldPath,
            dstFs: fs, dstRemote: newPath
        )
        await loadFiles()
    }
}
```

- [ ] **Step 2: Implement FileTable**

Write `Nimbus/Nimbus/Views/Browser/FileTable.swift`:

```swift
import SwiftUI
import RcloneKit

struct FileTable: View {
    let files: [FileItem]
    @Binding var selection: Set<String>
    @Binding var sortField: SortField
    @Binding var sortAscending: Bool
    let onOpen: (FileItem) -> Void
    let onContextAction: (FileItem, FileAction) -> Void

    var body: some View {
        Table(files, selection: $selection) {
            TableColumn("Name", sortUsing: KeyPathComparator(\.name)) { file in
                HStack(spacing: 8) {
                    Image(systemName: file.isDir ? "folder.fill" : iconName(for: file.name))
                        .foregroundStyle(file.isDir ? .blue : .secondary)
                    Text(file.name)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onOpen(file) }
            }

            TableColumn("Size") { file in
                Text(file.isDir ? "--" : formatSize(file.size))
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 80)

            TableColumn("Modified") { file in
                if let date = file.modTime {
                    Text(date, style: .date)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--").foregroundStyle(.secondary)
                }
            }
            .width(ideal: 120)
        }
        .contextMenu(forSelectionType: String.self) { paths in
            if let path = paths.first, let file = files.first(where: { $0.path == path }) {
                FileContextMenu(file: file, onAction: { action in
                    onContextAction(file, action)
                })
            }
        } primaryAction: { paths in
            if let path = paths.first, let file = files.first(where: { $0.path == path }) {
                onOpen(file)
            }
        }
    }

    private func iconName(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        case "mp4", "mov", "avi": return "film"
        case "mp3", "wav", "aac": return "music.note"
        case "zip", "tar", "gz": return "archivebox"
        case "txt", "md": return "doc.text"
        default: return "doc"
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
```

- [ ] **Step 3: Implement FileGrid**

Write `Nimbus/Nimbus/Views/Browser/FileGrid.swift`:

```swift
import SwiftUI
import RcloneKit

struct FileGrid: View {
    let files: [FileItem]
    @Binding var selection: Set<String>
    let onOpen: (FileItem) -> Void
    let onContextAction: (FileItem, FileAction) -> Void

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(files, id: \.path) { file in
                    VStack(spacing: 4) {
                        Image(systemName: file.isDir ? "folder.fill" : "doc")
                            .font(.system(size: 40))
                            .foregroundStyle(file.isDir ? .blue : .secondary)

                        Text(file.name)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 100, height: 90)
                    .padding(8)
                    .background(
                        selection.contains(file.path)
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .onTapGesture {
                        selection = [file.path]
                    }
                    .onTapGesture(count: 2) {
                        onOpen(file)
                    }
                    .contextMenu {
                        FileContextMenu(file: file, onAction: { action in
                            onContextAction(file, action)
                        })
                    }
                }
            }
            .padding()
        }
    }
}
```

- [ ] **Step 4: Implement FileContextMenu and FileAction**

Write `Nimbus/Nimbus/Views/Browser/FileContextMenu.swift`:

```swift
import SwiftUI
import RcloneKit

enum FileAction {
    case open
    case rename
    case delete
}

struct FileContextMenu: View {
    let file: FileItem
    let onAction: (FileAction) -> Void

    var body: some View {
        Button("Open") { onAction(.open) }
        Divider()
        Button("Rename") { onAction(.rename) }
        Divider()
        Button("Delete", role: .destructive) { onAction(.delete) }
    }
}
```

- [ ] **Step 5: Implement BrowserToolbar**

Write `Nimbus/Nimbus/Views/Browser/BrowserToolbar.swift`:

```swift
import SwiftUI

struct BrowserToolbar: ViewModifier {
    @Binding var viewMode: ViewMode
    @Binding var sortField: SortField
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onNewFolder: () -> Void
    let onRefresh: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)

                Button(action: onForward) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onNewFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Folder")

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                Picker("View", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                }
                .pickerStyle(.segmented)

                Picker("Sort", selection: $sortField) {
                    ForEach(SortField.allCases, id: \.self) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 6: Implement BrowserView**

Replace `Nimbus/Nimbus/Views/Browser/BrowserView.swift` (create if needed):

```swift
import SwiftUI
import RcloneKit

struct BrowserView: View {
    let remoteName: String
    @Environment(RcloneDaemon.self) private var daemon
    @State private var viewModel: BrowserViewModel?
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renamingFile: FileItem?
    @State private var renameText = ""

    var body: some View {
        Group {
            if let viewModel {
                VStack(spacing: 0) {
                    // Breadcrumb
                    breadcrumb(viewModel: viewModel)

                    Divider()

                    // File list or grid
                    if viewModel.isLoading && viewModel.files.isEmpty {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.files.isEmpty {
                        ContentUnavailableView(
                            "Empty Folder",
                            systemImage: "folder",
                            description: Text("This folder has no files.")
                        )
                    } else {
                        switch viewModel.viewMode {
                        case .list:
                            FileTable(
                                files: viewModel.sortedFiles,
                                selection: Binding(
                                    get: { viewModel.selection },
                                    set: { viewModel.selection = $0 }
                                ),
                                sortField: Binding(
                                    get: { viewModel.sortField },
                                    set: { viewModel.sortField = $0 }
                                ),
                                sortAscending: Binding(
                                    get: { viewModel.sortAscending },
                                    set: { viewModel.sortAscending = $0 }
                                ),
                                onOpen: { file in handleOpen(file, viewModel: viewModel) },
                                onContextAction: { file, action in handleAction(file, action, viewModel: viewModel) }
                            )
                        case .grid:
                            FileGrid(
                                files: viewModel.sortedFiles,
                                selection: Binding(
                                    get: { viewModel.selection },
                                    set: { viewModel.selection = $0 }
                                ),
                                onOpen: { file in handleOpen(file, viewModel: viewModel) },
                                onContextAction: { file, action in handleAction(file, action, viewModel: viewModel) }
                            )
                        }
                    }
                }
                .modifier(BrowserToolbar(
                    viewMode: Binding(
                        get: { viewModel.viewMode },
                        set: { viewModel.viewMode = $0 }
                    ),
                    sortField: Binding(
                        get: { viewModel.sortField },
                        set: { viewModel.sortField = $0 }
                    ),
                    canGoBack: viewModel.canGoBack,
                    canGoForward: viewModel.canGoForward,
                    onBack: { Task { await viewModel.goBack() } },
                    onForward: { Task { await viewModel.goForward() } },
                    onNewFolder: { showNewFolder = true },
                    onRefresh: { Task { await viewModel.loadFiles() } }
                ))
            }
        }
        .navigationTitle(remoteName)
        .task {
            let vm = BrowserViewModel(client: daemon.client)
            vm.remote = remoteName
            viewModel = vm
            await vm.loadFiles()
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                Task {
                    try? await viewModel?.createFolder(name: newFolderName)
                    newFolderName = ""
                }
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Rename", isPresented: Binding(
            get: { renamingFile != nil },
            set: { if !$0 { renamingFile = nil } }
        )) {
            TextField("New name", text: $renameText)
            Button("Rename") {
                if let file = renamingFile {
                    Task {
                        try? await viewModel?.renameItem(oldPath: file.path, newName: renameText)
                        renamingFile = nil
                        renameText = ""
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                renamingFile = nil
                renameText = ""
            }
        }
    }

    private func breadcrumb(viewModel: BrowserViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.pathComponents.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(component.name) {
                        Task { await viewModel.navigateTo(path: component.path) }
                    }
                    .buttonStyle(.plain)
                    .font(index == viewModel.pathComponents.count - 1 ? .body.bold() : .body)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func handleOpen(_ file: FileItem, viewModel: BrowserViewModel) {
        if file.isDir {
            Task { await viewModel.navigateTo(path: file.path) }
        }
    }

    private func handleAction(_ file: FileItem, _ action: FileAction, viewModel: BrowserViewModel) {
        switch action {
        case .open:
            handleOpen(file, viewModel: viewModel)
        case .rename:
            renamingFile = file
            renameText = file.name
        case .delete:
            Task { try? await viewModel.deleteItems(paths: [file.path]) }
        }
    }
}
```

- [ ] **Step 7: Wire BrowserView into navigation**

Update `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift` to expose `onBrowse`, and update `ContentView.swift` to handle browsing navigation.

Update `Nimbus/Nimbus/Views/ContentView.swift` — add a `browsingRemote` state:

```swift
import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .remotes
    @State private var browsingRemote: String?
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon

    var body: some View {
        if !settings.onboardingComplete {
            OnboardingView()
        } else {
            NavigationSplitView {
                Sidebar(selection: $selection)
                    .frame(minWidth: 180)
            } detail: {
                if let browsingRemote {
                    BrowserView(remoteName: browsingRemote)
                        .toolbar {
                            ToolbarItem(placement: .navigation) {
                                Button("Back to Remotes") {
                                    self.browsingRemote = nil
                                    self.selection = .remotes
                                }
                            }
                        }
                } else {
                    detailView
                }
            }
            .frame(minWidth: 800, minHeight: 600)
            .toolbar {
                if case .error(let message) = daemon.status {
                    ToolbarItem(placement: .status) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .environment(\.openBrowser, OpenBrowserAction { remote in
                browsingRemote = remote
            })
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .remotes:
            RemotesView()
        case .mounts:
            MountsView()
        case .transfers:
            TransfersView()
        case .copySync:
            CopySyncView()
        case .settings:
            SettingsView()
        case nil:
            Text("Select an item from the sidebar")
                .foregroundStyle(.secondary)
        }
    }
}

// Environment action for opening browser from RemoteRow
struct OpenBrowserAction {
    let action: (String) -> Void
    func callAsFunction(_ remote: String) { action(remote) }
}

extension EnvironmentValues {
    @Entry var openBrowser = OpenBrowserAction { _ in }
}
```

Update `RemotesView` to use the environment action for browse:

In `RemotesView.swift`, add `@Environment(\.openBrowser) private var openBrowser` and change `onBrowse` to call `openBrowser(remote.name)`.

- [ ] **Step 8: Build**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 9: Commit**

```bash
git add Nimbus/Nimbus/ViewModels/BrowserViewModel.swift Nimbus/Nimbus/Views/Browser/ Nimbus/Nimbus/Views/ContentView.swift
git commit -m "feat: add File Browser with table/grid views, navigation, and file operations"
```

---

## Task 13: Mounts Views + ViewModel

**Files:**
- Create: `Nimbus/Nimbus/ViewModels/MountsViewModel.swift`
- Modify: `Nimbus/Nimbus/Views/Mounts/MountsView.swift`
- Create: `Nimbus/Nimbus/Views/Mounts/MountRow.swift`
- Create: `Nimbus/Nimbus/Views/Mounts/AddMountSheet.swift`

- [ ] **Step 1: Implement MountsViewModel**

Write `Nimbus/Nimbus/ViewModels/MountsViewModel.swift`:

```swift
import Foundation
import Observation
import RcloneKit

@Observable
@MainActor
final class MountsViewModel {
    private(set) var remoteNames: [String] = []
    private(set) var error: String?

    private let client: RcloneClient

    init(client: RcloneClient) {
        self.client = client
    }

    func loadRemotes() async {
        do {
            remoteNames = try await client.listRemotes()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Implement MountRow**

Write `Nimbus/Nimbus/Views/Mounts/MountRow.swift`:

```swift
import SwiftUI

struct MountRow: View {
    let config: MountConfig
    let isActive: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isActive ? "externaldrive.fill.badge.checkmark" : "externaldrive")
                .foregroundStyle(isActive ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading) {
                Text(config.remote)
                    .font(.headline)
                Text(config.mountPoint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(config.vfsMode.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Text(config.backend.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            Spacer()

            Button(isActive ? "Unmount" : "Mount") {
                onToggle()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Remove", role: .destructive) { onRemove() }
        }
    }
}
```

- [ ] **Step 3: Implement AddMountSheet**

Write `Nimbus/Nimbus/Views/Mounts/AddMountSheet.swift`:

```swift
import SwiftUI

struct AddMountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MountConfigStore.self) private var configStore
    let remoteNames: [String]

    @State private var selectedRemote = ""
    @State private var mountPoint = ""
    @State private var vfsMode: VFSMode = .readWrite
    @State private var backend: MountBackend = .nfs
    @State private var autoMount = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Remote", selection: $selectedRemote) {
                    Text("Select...").tag("")
                    ForEach(remoteNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                TextField("Mount Point", text: $mountPoint, prompt: Text("~/CloudDrives/remote-name"))

                Picker("Mode", selection: $vfsMode) {
                    ForEach(VFSMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Backend", selection: $backend) {
                    ForEach(MountBackend.allCases, id: \.self) { b in
                        Text(b.rawValue).tag(b)
                    }
                }

                Toggle("Auto-mount on startup", isOn: $autoMount)
            }
            .navigationTitle("Add Mount")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let config = MountConfig(
                            remote: "\(selectedRemote):",
                            mountPoint: expandTilde(mountPoint),
                            vfsMode: vfsMode,
                            autoMount: autoMount,
                            backend: backend
                        )
                        configStore.addConfig(config)
                        dismiss()
                    }
                    .disabled(selectedRemote.isEmpty || mountPoint.isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
```

- [ ] **Step 4: Implement MountsView**

Replace `Nimbus/Nimbus/Views/Mounts/MountsView.swift`:

```swift
import SwiftUI
import RcloneKit

struct MountsView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(MountConfigStore.self) private var configStore
    @Environment(MountManager.self) private var mountManager
    @State private var viewModel: MountsViewModel?
    @State private var showAddMount = false

    var body: some View {
        Group {
            if configStore.configs.isEmpty {
                ContentUnavailableView(
                    "No Mounts",
                    systemImage: "externaldrive",
                    description: Text("Add a mount to access cloud files as a local drive.")
                )
            } else {
                List(configStore.configs) { config in
                    let isActive = mountManager.activeMounts.contains { $0.mountPoint == config.mountPoint }
                    MountRow(
                        config: config,
                        isActive: isActive,
                        onToggle: { Task { await toggleMount(config: config, isActive: isActive) } },
                        onRemove: { configStore.removeConfig(id: config.id) }
                    )
                }
            }
        }
        .navigationTitle("Mounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Mount", systemImage: "plus") {
                    showAddMount = true
                }
            }
        }
        .task {
            let vm = MountsViewModel(client: daemon.client)
            viewModel = vm
            await vm.loadRemotes()
        }
        .sheet(isPresented: $showAddMount) {
            AddMountSheet(remoteNames: viewModel?.remoteNames ?? [])
        }
    }

    private func toggleMount(config: MountConfig, isActive: Bool) async {
        if isActive {
            try? await mountManager.unmount(mountPoint: config.mountPoint)
        } else {
            try? await mountManager.mount(
                remote: config.remote,
                mountPoint: config.mountPoint,
                readOnly: config.vfsMode == .readOnly
            )
        }
    }
}
```

- [ ] **Step 5: Build**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 6: Commit**

```bash
git add Nimbus/Nimbus/ViewModels/MountsViewModel.swift Nimbus/Nimbus/Views/Mounts/
git commit -m "feat: add Mounts views with mount/unmount toggle and add mount sheet"
```

---

## Task 14: Transfers + Copy-Sync Views + ViewModels

**Files:**
- Create: `Nimbus/Nimbus/ViewModels/TransfersViewModel.swift`
- Create: `Nimbus/Nimbus/ViewModels/CopySyncViewModel.swift`
- Modify: `Nimbus/Nimbus/Views/Transfers/TransfersView.swift`
- Create: `Nimbus/Nimbus/Views/Transfers/TransferRow.swift`
- Modify: `Nimbus/Nimbus/Views/CopySync/CopySyncView.swift`
- Create: `Nimbus/Nimbus/Views/CopySync/PathPicker.swift`

- [ ] **Step 1: Implement TransfersViewModel**

Write `Nimbus/Nimbus/ViewModels/TransfersViewModel.swift`:

```swift
import Foundation
import Observation
import RcloneKit

@Observable
@MainActor
final class TransfersViewModel {
    private(set) var overallStats: StatsResponse?
    private(set) var error: String?

    private let client: RcloneClient
    private var statsTask: Task<Void, Never>?

    init(client: RcloneClient) {
        self.client = client
    }

    func startStatsPolling() {
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchStats()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopStatsPolling() {
        statsTask?.cancel()
        statsTask = nil
    }

    func cancelJob(id: Int) async {
        do {
            try await client.stopJob(id: id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchStats() async {
        do {
            overallStats = try await client.getStats()
        } catch {
            // Transient — keep polling
        }
    }
}
```

- [ ] **Step 2: Implement TransferRow**

Write `Nimbus/Nimbus/Views/Transfers/TransferRow.swift`:

```swift
import SwiftUI

struct TransferRow: View {
    let transfer: Transfer
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Image(systemName: transfer.operation == .copy ? "doc.on.doc" : "arrow.triangle.2.circlepath")
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(transfer.srcFs) → \(transfer.dstFs)")
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    statusBadge
                    if let completedAt = transfer.completedAt {
                        Text(completedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if case .active = transfer.status {
                Button(role: .destructive) {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch transfer.status {
        case .active:
            Label("Active", systemImage: "arrow.up.arrow.down")
                .font(.caption)
                .foregroundStyle(.blue)
        case .completed:
            Label("Completed", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        case .cancelled:
            Label("Cancelled", systemImage: "minus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Implement TransfersView**

Replace `Nimbus/Nimbus/Views/Transfers/TransfersView.swift`:

```swift
import SwiftUI
import RcloneKit

struct TransfersView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var store
    @State private var viewModel: TransfersViewModel?

    var body: some View {
        Group {
            if store.transfers.isEmpty {
                ContentUnavailableView(
                    "No Transfers",
                    systemImage: "arrow.up.arrow.down",
                    description: Text("Copy or sync operations will appear here.")
                )
            } else {
                List {
                    if !store.activeTransfers.isEmpty {
                        Section("Active") {
                            ForEach(store.activeTransfers) { transfer in
                                TransferRow(transfer: transfer) {
                                    Task {
                                        await viewModel?.cancelJob(id: transfer.id)
                                        store.cancelTransfer(jobId: transfer.id)
                                    }
                                }
                            }
                        }
                    }

                    if !store.completedTransfers.isEmpty {
                        Section("Completed") {
                            ForEach(store.completedTransfers) { transfer in
                                TransferRow(transfer: transfer, onCancel: {})
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Transfers")
        .toolbar {
            if !store.completedTransfers.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear Completed") {
                        store.clearCompleted()
                    }
                }
            }
        }
        .task {
            let vm = TransfersViewModel(client: daemon.client)
            viewModel = vm
            vm.startStatsPolling()
        }
        .onDisappear {
            viewModel?.stopStatsPolling()
        }
    }
}
```

- [ ] **Step 4: Implement CopySyncViewModel**

Write `Nimbus/Nimbus/ViewModels/CopySyncViewModel.swift`:

```swift
import Foundation
import Observation
import RcloneKit

@Observable
@MainActor
final class CopySyncViewModel {
    private(set) var remoteNames: [String] = []
    private(set) var error: String?

    private let client: RcloneClient

    init(client: RcloneClient) {
        self.client = client
    }

    func loadRemotes() async {
        do {
            remoteNames = try await client.listRemotes()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startOperation(
        operation: TransferOperation,
        srcFs: String,
        dstFs: String,
        store: TransferStore
    ) async throws {
        let jobId: Int
        switch operation {
        case .copy:
            jobId = try await client.copy(srcFs: srcFs, dstFs: dstFs)
        case .sync:
            jobId = try await client.sync(srcFs: srcFs, dstFs: dstFs)
        }
        store.addTransfer(jobId: jobId, operation: operation, srcFs: srcFs, dstFs: dstFs)
    }
}
```

- [ ] **Step 5: Implement PathPicker**

Write `Nimbus/Nimbus/Views/CopySync/PathPicker.swift`:

```swift
import SwiftUI
import RcloneKit

struct PathPicker: View {
    let label: String
    let remoteNames: [String]
    @Binding var selectedRemote: String
    @Binding var path: String

    var body: some View {
        GroupBox(label) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Remote", selection: $selectedRemote) {
                    Text("Select...").tag("")
                    ForEach(remoteNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                TextField("Path", text: $path, prompt: Text("e.g., documents/photos"))
            }
            .padding(8)
        }
    }
}
```

- [ ] **Step 6: Implement CopySyncView**

Replace `Nimbus/Nimbus/Views/CopySync/CopySyncView.swift`:

```swift
import SwiftUI
import RcloneKit

struct CopySyncView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var store
    @State private var viewModel: CopySyncViewModel?

    @State private var operation: TransferOperation = .copy
    @State private var srcRemote = ""
    @State private var srcPath = ""
    @State private var dstRemote = ""
    @State private var dstPath = ""
    @State private var isRunning = false
    @State private var error: String?

    var body: some View {
        Form {
            Picker("Operation", selection: $operation) {
                Text("Copy").tag(TransferOperation.copy)
                Text("Sync").tag(TransferOperation.sync)
            }
            .pickerStyle(.segmented)

            if operation == .sync {
                Text("Sync will make the destination identical to the source. Files in the destination that don't exist in the source will be deleted.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let remotes = viewModel?.remoteNames {
                PathPicker(
                    label: "Source",
                    remoteNames: remotes,
                    selectedRemote: $srcRemote,
                    path: $srcPath
                )

                PathPicker(
                    label: "Destination",
                    remoteNames: remotes,
                    selectedRemote: $dstRemote,
                    path: $dstPath
                )
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
            }

            Button(operation == .copy ? "Start Copy" : "Start Sync") {
                Task { await startOperation() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(srcRemote.isEmpty || dstRemote.isEmpty || isRunning)
        }
        .padding()
        .navigationTitle("Copy / Sync")
        .task {
            let vm = CopySyncViewModel(client: daemon.client)
            viewModel = vm
            await vm.loadRemotes()
        }
    }

    private func startOperation() async {
        isRunning = true
        error = nil
        defer { isRunning = false }

        let srcFs = srcPath.isEmpty ? "\(srcRemote):" : "\(srcRemote):\(srcPath)"
        let dstFs = dstPath.isEmpty ? "\(dstRemote):" : "\(dstRemote):\(dstPath)"

        do {
            try await viewModel?.startOperation(
                operation: operation,
                srcFs: srcFs,
                dstFs: dstFs,
                store: store
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

- [ ] **Step 7: Build**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 8: Commit**

```bash
git add Nimbus/Nimbus/ViewModels/TransfersViewModel.swift Nimbus/Nimbus/ViewModels/CopySyncViewModel.swift \
       Nimbus/Nimbus/Views/Transfers/ Nimbus/Nimbus/Views/CopySync/
git commit -m "feat: add Transfers and Copy/Sync views with job monitoring"
```

---

## Task 15: File Provider Extension Refactor

**Files:**
- Modify: `FileProviderExtension/Extension.swift`
- Modify: `FileProviderExtension/Enumerator.swift`
- Modify: `FileProviderExtension/Item.swift`
- Delete: `src-tauri/FileProviderExtension/SharedState.swift`
- Delete: `src-tauri/FileProviderExtension/DomainManager.swift`
- Delete: `src-tauri/FileProviderExtension/RcloneClient.swift`

The File Provider extension files need to be moved from `src-tauri/FileProviderExtension/` to the new Xcode project's `FileProviderExtension/` target and refactored to use RcloneKit.

- [ ] **Step 1: Create new Extension.swift using RcloneKit**

Write `Nimbus/FileProviderExtension/Extension.swift`:

```swift
import FileProvider
import RcloneKit
import os
import UniformTypeIdentifiers

final class FileProviderExtension: NSFileProviderReplicatedExtension, @unchecked Sendable {
    let domain: NSFileProviderDomain
    let rclone: RcloneClient
    private let logger = Logger(subsystem: "com.nimbus.app.FileProvider", category: "extension")

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        let port = Self.readPort()
        self.rclone = RcloneClient(port: port)
        logger.info("Extension initialized for domain \(domain.identifier.rawValue) on port \(port)")
    }

    func invalidate() {}

    // MARK: - Item Lookup

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
        if identifier == .rootContainer {
            completionHandler(FileProviderItem.rootContainer(domain: domain), nil)
            return Progress()
        }

        Task {
            do {
                let item = try await fetchItem(identifier: identifier)
                completionHandler(item, nil)
            } catch {
                logger.error("item(for:) failed: \(error)")
                completionHandler(nil, error)
            }
        }
        return Progress()
    }

    // MARK: - Enumeration

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> any NSFileProviderEnumerator {
        FileProviderEnumerator(
            containerIdentifier: containerItemIdentifier,
            rclone: rclone,
            domain: domain
        )
    }

    // MARK: - Download

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
        Task {
            do {
                let remotePath = extractPath(from: itemIdentifier)
                let remoteName = domain.identifier.rawValue

                // Download to temp
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("com.nimbus.fileprovider", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let filename = (remotePath as NSString).lastPathComponent
                let localURL = tempDir.appendingPathComponent(filename)

                // Copy from remote to local temp
                try await rclone.copyFile(
                    srcFs: "\(remoteName):",
                    srcRemote: remotePath,
                    dstFs: "/",
                    dstRemote: localURL.path
                )

                let item = try await fetchItem(identifier: itemIdentifier)
                completionHandler(localURL, item, nil)
            } catch {
                logger.error("fetchContents failed: \(error)")
                completionHandler(nil, nil, error)
            }
        }
        return Progress()
    }

    // MARK: - Create

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
    ) -> Progress {
        Task {
            do {
                let parentPath = extractPath(from: itemTemplate.parentItemIdentifier)
                let remoteName = domain.identifier.rawValue
                let newPath = parentPath.isEmpty
                    ? itemTemplate.filename
                    : "\(parentPath)/\(itemTemplate.filename)"

                if itemTemplate.contentType == .folder {
                    try await rclone.mkdir(fs: "\(remoteName):", remote: newPath)
                } else if let url {
                    try await rclone.copyFile(
                        srcFs: "/",
                        srcRemote: url.path,
                        dstFs: "\(remoteName):",
                        dstRemote: newPath
                    )
                }

                let item = try await fetchItem(
                    identifier: NSFileProviderItemIdentifier("\(remoteName):\(newPath)")
                )
                completionHandler(item, [], false, nil)
            } catch {
                logger.error("createItem failed: \(error)")
                completionHandler(nil, [], false, error)
            }
        }
        return Progress()
    }

    // MARK: - Modify

    func modifyItem(
        _ identifier: NSFileProviderItemIdentifier,
        baseVersion: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
    ) -> Progress {
        Task {
            do {
                let remoteName = domain.identifier.rawValue
                var currentPath = extractPath(from: identifier)

                if changedFields.contains(.contents), let url = newContents {
                    try await rclone.copyFile(
                        srcFs: "/",
                        srcRemote: url.path,
                        dstFs: "\(remoteName):",
                        dstRemote: currentPath
                    )
                }

                if changedFields.contains(.filename) {
                    // Need the template item to get new filename — not available here
                    // This is handled by the File Provider framework passing the new name
                }

                let item = try await fetchItem(
                    identifier: NSFileProviderItemIdentifier("\(remoteName):\(currentPath)")
                )
                completionHandler(item, [], false, nil)
            } catch {
                logger.error("modifyItem failed: \(error)")
                completionHandler(nil, [], false, error)
            }
        }
        return Progress()
    }

    // MARK: - Delete

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> Progress {
        Task {
            do {
                let remoteName = domain.identifier.rawValue
                let remotePath = extractPath(from: identifier)
                try await rclone.deleteFile(fs: "\(remoteName):", remote: remotePath)
                completionHandler(nil)
            } catch {
                logger.error("deleteItem failed: \(error)")
                completionHandler(error)
            }
        }
        return Progress()
    }

    // MARK: - Helpers

    private func fetchItem(identifier: NSFileProviderItemIdentifier) async throws -> FileProviderItem {
        let remoteName = domain.identifier.rawValue
        let remotePath = extractPath(from: identifier)
        let parentPath = (remotePath as NSString).deletingLastPathComponent
        let filename = (remotePath as NSString).lastPathComponent

        let files = try await rclone.listFiles(fs: "\(remoteName):", remote: parentPath)
        guard let file = files.first(where: { $0.name == filename }) else {
            throw NSFileProviderError(.noSuchItem)
        }

        let parentId = parentPath.isEmpty
            ? NSFileProviderItemIdentifier.rootContainer
            : NSFileProviderItemIdentifier("\(remoteName):\(parentPath)")

        return FileProviderItem(from: file, parentIdentifier: parentId, remoteName: remoteName)
    }

    private func extractPath(from identifier: NSFileProviderItemIdentifier) -> String {
        let raw = identifier.rawValue
        let remoteName = domain.identifier.rawValue
        let prefix = "\(remoteName):"
        if raw.hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
        }
        return raw
    }

    private static func readPort() -> Int {
        let defaults = UserDefaults(suiteName: "group.com.nimbus.app")
        return defaults?.integer(forKey: "rclonePort") ?? 5572
    }
}
```

- [ ] **Step 2: Create new Item.swift using RcloneKit types**

Write `Nimbus/FileProviderExtension/Item.swift`:

```swift
import FileProvider
import RcloneKit
import UniformTypeIdentifiers

final class FileProviderItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType
    let documentSize: NSNumber?
    let contentModificationDate: Date?
    let creationDate: Date?
    let itemVersion: NSFileProviderItemVersion

    let capabilities: NSFileProviderItemCapabilities
    let contentPolicy: NSFileProviderContentPolicy = .downloadLazily

    init(from file: FileItem, parentIdentifier: NSFileProviderItemIdentifier, remoteName: String) {
        self.itemIdentifier = NSFileProviderItemIdentifier("\(remoteName):\(file.path)")
        self.parentItemIdentifier = parentIdentifier
        self.filename = file.name
        self.contentModificationDate = file.modTime
        self.creationDate = file.modTime

        if file.isDir {
            self.contentType = .folder
            self.documentSize = nil
            self.capabilities = [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming, .allowsDeleting]
        } else {
            self.contentType = UTType(filenameExtension: (file.name as NSString).pathExtension) ?? .data
            self.documentSize = NSNumber(value: file.size)
            self.capabilities = [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting]
        }

        // Version from modification date
        let versionData: Data
        if let modTime = file.modTime {
            versionData = withUnsafeBytes(of: modTime.timeIntervalSince1970) { Data($0) }
        } else {
            versionData = Data([0])
        }
        self.itemVersion = NSFileProviderItemVersion(contentVersion: versionData, metadataVersion: versionData)
    }

    private init(identifier: NSFileProviderItemIdentifier, parent: NSFileProviderItemIdentifier, name: String) {
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parent
        self.filename = name
        self.contentType = .folder
        self.documentSize = nil
        self.contentModificationDate = nil
        self.creationDate = nil
        self.capabilities = [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems]
        self.itemVersion = NSFileProviderItemVersion(contentVersion: Data([0]), metadataVersion: Data([0]))
    }

    static func rootContainer(domain: NSFileProviderDomain) -> FileProviderItem {
        FileProviderItem(
            identifier: .rootContainer,
            parent: .rootContainer,
            name: domain.displayName
        )
    }
}
```

- [ ] **Step 3: Create new Enumerator.swift using RcloneKit**

Write `Nimbus/FileProviderExtension/Enumerator.swift`:

```swift
import FileProvider
import RcloneKit
import os

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {
    private let containerIdentifier: NSFileProviderItemIdentifier
    private let rclone: RcloneClient
    private let domain: NSFileProviderDomain
    private var cachedFiles: [String: FileItem] = [:] // path → FileItem
    private let logger = Logger(subsystem: "com.nimbus.app.FileProvider", category: "enumerator")

    init(
        containerIdentifier: NSFileProviderItemIdentifier,
        rclone: RcloneClient,
        domain: NSFileProviderDomain
    ) {
        self.containerIdentifier = containerIdentifier
        self.rclone = rclone
        self.domain = domain
    }

    func invalidate() {}

    func enumerateItems(
        for observer: any NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        Task {
            do {
                let remoteName = domain.identifier.rawValue
                let remotePath = extractPath()
                let files = try await rclone.listFiles(fs: "\(remoteName):", remote: remotePath)

                // Cache for change diffing
                cachedFiles = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })

                let parentId = containerIdentifier
                let items = files.map { FileProviderItem(from: $0, parentIdentifier: parentId, remoteName: remoteName) }

                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch {
                logger.error("enumerateItems failed: \(error)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(
        for observer: any NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) {
        Task {
            do {
                let remoteName = domain.identifier.rawValue
                let remotePath = extractPath()
                let files = try await rclone.listFiles(fs: "\(remoteName):", remote: remotePath)

                let newFilesByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
                let parentId = containerIdentifier

                // Find updates and additions
                var updatedItems: [NSFileProviderItem] = []
                for file in files {
                    if let cached = cachedFiles[file.path] {
                        // Check if modified
                        if cached.size != file.size || cached.modTime != file.modTime {
                            updatedItems.append(FileProviderItem(from: file, parentIdentifier: parentId, remoteName: remoteName))
                        }
                    } else {
                        // New item
                        updatedItems.append(FileProviderItem(from: file, parentIdentifier: parentId, remoteName: remoteName))
                    }
                }

                // Find deletions
                var deletedIds: [NSFileProviderItemIdentifier] = []
                for path in cachedFiles.keys {
                    if newFilesByPath[path] == nil {
                        deletedIds.append(NSFileProviderItemIdentifier("\(remoteName):\(path)"))
                    }
                }

                cachedFiles = newFilesByPath

                if !updatedItems.isEmpty {
                    observer.didUpdate(updatedItems)
                }
                if !deletedIds.isEmpty {
                    observer.didDeleteItems(withIdentifiers: deletedIds)
                }

                let anchorData = withUnsafeBytes(of: Date().timeIntervalSince1970) { Data($0) }
                observer.finishEnumeratingChanges(
                    upTo: NSFileProviderSyncAnchor(anchorData),
                    moreComing: false
                )
            } catch {
                logger.error("enumerateChanges failed: \(error)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let data = withUnsafeBytes(of: Date().timeIntervalSince1970) { Data($0) }
        completionHandler(NSFileProviderSyncAnchor(data))
    }

    private func extractPath() -> String {
        let raw = containerIdentifier.rawValue
        let remoteName = domain.identifier.rawValue
        let prefix = "\(remoteName):"
        if raw.hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
        }
        if containerIdentifier == .rootContainer {
            return ""
        }
        return raw
    }
}
```

- [ ] **Step 4: Add FileProviderExtension target to Xcode project**

In Xcode:
- File → New → Target → macOS → File Provider Extension
- Name: `FileProviderExtension`
- Bundle Identifier: `com.nimbus.app.FileProvider`
- Add RcloneKit dependency to the extension target
- Replace generated files with the ones written above
- Set app group entitlement: `group.com.nimbus.app`
- Set network client entitlement: `com.apple.security.network.client`

- [ ] **Step 5: Build**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 6: Commit**

```bash
git add Nimbus/FileProviderExtension/
git commit -m "feat: refactor File Provider extension to use shared RcloneKit package"
```

---

## Task 16: File Provider Sync Hook + Keyboard Shortcuts

**Files:**
- Modify: `Nimbus/Nimbus/NimbusApp.swift`

- [ ] **Step 1: Add File Provider sync to app lifecycle**

In `NimbusApp.swift`, update the `startApp()` function to sync File Provider state after daemon connects:

Add after the daemon start block in `startApp()`:

```swift
// Sync File Provider domains
if daemon.status == .connected {
    do {
        let remotes = try await daemon.client.listRemotes()
        fileProviderBridge.syncState(remotes: remotes, port: daemon.port)

        // Add domains for each remote
        for remote in remotes {
            try? await fileProviderBridge.addDomain(identifier: remote, displayName: remote)
        }

        // Clean up stale domains
        _ = await fileProviderBridge.cleanupStaleDomains(activeRemotes: remotes)
    } catch {
        // Non-fatal — app works without File Provider
    }
}
```

- [ ] **Step 2: Add keyboard shortcuts**

Add to `ContentView.swift`:

```swift
.keyboardShortcut("1", modifiers: .command) // handled per-item below
.onKeyPress(.init("1"), modifiers: .command) { selection = .remotes; return .handled }
.onKeyPress(.init("2"), modifiers: .command) { selection = .mounts; return .handled }
.onKeyPress(.init("3"), modifiers: .command) { selection = .transfers; return .handled }
.onKeyPress(.init("4"), modifiers: .command) { selection = .copySync; return .handled }
.onKeyPress(.init(","), modifiers: .command) { selection = .settings; return .handled }
```

- [ ] **Step 3: Build and verify**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 4: Commit**

```bash
git add Nimbus/Nimbus/
git commit -m "feat: add File Provider sync on startup and keyboard shortcuts"
```

---

## Task 17: Window Close-to-Tray Behavior

**Files:**
- Create: `Nimbus/Nimbus/AppDelegate.swift`
- Modify: `Nimbus/Nimbus/NimbusApp.swift`

- [ ] **Step 1: Implement close-to-tray via AppDelegate**

Write `Nimbus/Nimbus/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
```

In `NimbusApp.swift`, add:

```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

And add window close behavior. In the `WindowGroup`:

```swift
WindowGroup {
    ContentView()
        // ... existing modifiers
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if let window = notification.object as? NSWindow {
                window.orderOut(nil) // hide instead of close
            }
        }
}
```

- [ ] **Step 2: Build and test**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 3: Commit**

```bash
git add Nimbus/Nimbus/AppDelegate.swift Nimbus/Nimbus/NimbusApp.swift
git commit -m "feat: add close-to-tray behavior and app delegate"
```

---

## Task 18: Entitlements & Info.plist Configuration

**Files:**
- Modify: `Nimbus/Nimbus/Nimbus.entitlements`
- Modify: `Nimbus/FileProviderExtension/FileProviderExtension.entitlements`

- [ ] **Step 1: Configure app entitlements**

The main app needs these entitlements (in Xcode signing & capabilities):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.nimbus.app</string>
    </array>
</dict>
</plist>
```

Note: Sandbox is disabled because the app needs to run `rclone` and `mount_nfs` as child processes and access arbitrary mount points.

The extension entitlements:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.nimbus.app</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Build and verify**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

- [ ] **Step 3: Commit**

```bash
git add Nimbus/
git commit -m "feat: configure entitlements for app and File Provider extension"
```

---

## Task 19: Delete Old Codebase

**Files:**
- Delete: `src/` (all React/TypeScript)
- Delete: `src-tauri/` (all Rust + old Swift extension)
- Delete: `package.json`, `package-lock.json`, `tsconfig.json`, `tsconfig.node.json`
- Delete: `vite.config.ts`, `tailwind.config.ts`, `biome.json`
- Delete: `scripts/`
- Delete: `index.html`
- Delete: `postcss.config.js`
- Keep: `docs/`, `RcloneKit/`, `Nimbus/`, `.git/`, `CLAUDE.md`

- [ ] **Step 1: Remove old source directories**

```bash
cd /Volumes/DATA/Dev/Nimbus
rm -rf src/ src-tauri/ scripts/ node_modules/
rm -f package.json package-lock.json tsconfig.json tsconfig.node.json
rm -f vite.config.ts tailwind.config.ts biome.json
rm -f index.html postcss.config.js components.json
```

- [ ] **Step 2: Update CLAUDE.md for new architecture**

Update `CLAUDE.md` to reflect the Swift/SwiftUI project. Remove all references to npm, Tauri, Rust, React, Vite, Biome. Replace with Xcode build commands and the new project structure.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove Tauri/React/Rust codebase, replaced by native Swift/SwiftUI"
```

---

## Task 20: Integration Testing

- [ ] **Step 1: Run all RcloneKit tests**

```bash
cd /Volumes/DATA/Dev/Nimbus/RcloneKit
swift test
```

Expected: All unit tests pass.

- [ ] **Step 2: Build entire project**

```bash
cd /Volumes/DATA/Dev/Nimbus/Nimbus
xcodebuild -scheme Nimbus -destination 'platform=macOS' build
```

Expected: Clean build with no errors.

- [ ] **Step 3: Manual smoke test**

Launch the app from Xcode (Cmd+R) and verify:

1. Onboarding screen appears on first launch
2. Rclone daemon starts and connects (checkmark appears)
3. Can add a remote (test with `local` provider — no auth needed)
4. Can browse files in the remote
5. Navigation (back/forward, breadcrumb) works
6. Can create a folder, rename it, delete it
7. Settings tabs render correctly
8. Menu bar icon appears with Show/Quit items
9. Close window hides to tray, menu bar "Show" brings it back
10. Quit cleans up daemon process

- [ ] **Step 4: Test File Provider**

1. After adding a remote, check Finder sidebar for the File Provider domain
2. Click the domain — files should enumerate
3. Double-click a file — it should download and open

- [ ] **Step 5: Test NFS mounts**

1. Add a mount config for a local remote
2. Click Mount — should mount at the specified path
3. `ls` the mount point — files should appear
4. Click Unmount — mount point should be cleaned up

- [ ] **Step 6: Commit final state**

```bash
git add -A
git commit -m "chore: integration testing complete, native SwiftUI app functional"
```
