import Foundation
@testable import Nimbus
@testable import RcloneKit

/// Test double for the `RemoteProbeClient` protocol. Captures call args
/// and returns canned responses or throws canned errors per fs argument.
///
/// `about` runs concurrently (probeAll fans out on the global executor), so
/// the recorded calls and canned results sit behind a lock. Without it two
/// overlapping appends can drop one, which made CloudMonitor's probe test
/// flaky on CI.
final class MockRcloneClient: RemoteProbeClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _aboutResults: [String: Result<AboutResponse, Error>] = [:]
    private var _calls: [String] = []

    var aboutResults: [String: Result<AboutResponse, Error>] {
        get { lock.withLock { _aboutResults } }
        set { lock.withLock { _aboutResults = newValue } }
    }

    var calls: [String] { lock.withLock { _calls } }

    func about(fs: String) async throws -> AboutResponse {
        let result: Result<AboutResponse, Error>? = lock.withLock {
            _calls.append(fs)
            return _aboutResults[fs]
        }
        guard let result else {
            return Self.emptyAbout()
        }
        switch result {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    /// `AboutResponse` has only the public memberwise init synthesised by
    /// `Codable`; its stored properties are `let`. Decoding empty JSON
    /// avoids depending on a (currently-internal) memberwise initialiser
    /// and gives every field a `nil` value.
    static func emptyAbout() -> AboutResponse {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(AboutResponse.self, from: Data("{}".utf8))
    }
}
