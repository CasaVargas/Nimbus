import Foundation
import Testing
@testable import RcloneKit

/// Dedicated transport for `FixedTopLevelTests` so concurrent suites never share
/// `config/get` state.
private final class FixedTopLevelURLProtocol: URLProtocol, @unchecked Sendable {
    enum Mode {
        case configs([String: String])
        case status(Int, String)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var mode: Mode = .configs([:])

    static func setMode(_ newMode: Mode) {
        lock.withLock { mode = newMode }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "http://127.0.0.1")!
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        let name = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["name"] as? String
        let (status, json): (Int, String) = Self.lock.withLock {
            switch Self.mode {
            case .configs(let map):
                (200, name.flatMap { map[$0] } ?? "{}")
            case .status(let code, let payload):
                (code, payload)
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Fixed top-level remotes", .serialized)
struct FixedTopLevelTests {
    private func client(configs: [String: String]) -> RcloneClient {
        FixedTopLevelURLProtocol.setMode(.configs(configs))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixedTopLevelURLProtocol.self]
        return RcloneClient(port: 5572, session: URLSession(configuration: config))
    }

    private func failingClient(status: Int, body: String) -> RcloneClient {
        FixedTopLevelURLProtocol.setMode(.status(status, body))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixedTopLevelURLProtocol.self]
        return RcloneClient(port: 5572, session: URLSession(configuration: config))
    }

    @Test func combineRemoteAtRootIsTrue() async throws {
        let client = client(configs: ["clouds": #"{"type": "combine"}"#])
        #expect(try await client.hasFixedTopLevel(fs: "clouds:"))
    }

    @Test func combineRemoteSubpathIsFalse() async throws {
        let client = client(configs: ["clouds": #"{"type": "combine"}"#])
        #expect(try await !client.hasFixedTopLevel(fs: "clouds:gdrive"))
    }

    @Test func aliasToCombineRootIsTrue() async throws {
        let client = client(configs: [
            "x": #"{"type": "alias", "remote": "clouds:"}"#,
            "clouds": #"{"type": "combine"}"#,
        ])
        #expect(try await client.hasFixedTopLevel(fs: "x:"))
    }

    @Test func aliasToCombineSubpathIsFalse() async throws {
        let client = client(configs: [
            "y": #"{"type": "alias", "remote": "clouds:gdrive"}"#,
            "clouds": #"{"type": "combine"}"#,
        ])
        #expect(try await !client.hasFixedTopLevel(fs: "y:"))
    }

    @Test func cryptOverCombineRootIsTrue() async throws {
        let client = client(configs: [
            "vault": #"{"type": "crypt", "remote": "clouds:"}"#,
            "clouds": #"{"type": "combine"}"#,
        ])
        #expect(try await client.hasFixedTopLevel(fs: "vault:"))
    }

    @Test func nonCombineRemoteIsFalse() async throws {
        let client = client(configs: ["gdrive": #"{"type": "drive"}"#])
        #expect(try await !client.hasFixedTopLevel(fs: "gdrive:"))
    }

    @Test func unknownRemoteIsFalse() async throws {
        let client = client(configs: [:])
        #expect(try await !client.hasFixedTopLevel(fs: "missing:"))
    }

    @Test func wrapperCycleTerminatesAndIsFalse() async throws {
        let client = client(configs: [
            "a": #"{"type": "alias", "remote": "b:"}"#,
            "b": #"{"type": "alias", "remote": "a:"}"#,
        ])
        #expect(try await !client.hasFixedTopLevel(fs: "a:"))
    }

    @Test func configGetErrorPropagates() async {
        // Guards depend on errors throwing rather than collapsing to `false`.
        let client = failingClient(status: 500, body: #"{"error": "daemon busy"}"#)
        await #expect(throws: RcloneError.self) {
            _ = try await client.hasFixedTopLevel(fs: "clouds:")
        }
    }
}
