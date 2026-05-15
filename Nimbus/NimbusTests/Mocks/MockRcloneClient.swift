import Foundation
@testable import Nimbus
@testable import RcloneKit

/// Test double for the `RemoteProbeClient` protocol. Captures call args
/// and returns canned responses or throws canned errors per fs argument.
final class MockRcloneClient: RemoteProbeClient, @unchecked Sendable {
    var aboutResults: [String: Result<AboutResponse, Error>] = [:]
    private(set) var calls: [String] = []

    func about(fs: String) async throws -> AboutResponse {
        calls.append(fs)
        guard let result = aboutResults[fs] else {
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
