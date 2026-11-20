import Foundation
import Testing
@testable import RcloneKit

/// Answers every request with `reply` and keeps the last request body. Its
/// own session, so it shares no `operations/stat` state with
/// `MockURLProtocol`, whose other suites run concurrently with this one.
private final class StatURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedReply = "{}"
    nonisolated(unsafe) private static var storedBody: Data?

    static var lastBody: Data? { lock.withLock { storedBody } }

    static func client(replying reply: String) -> RcloneClient {
        lock.withLock {
            storedReply = reply
            storedBody = nil
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StatURLProtocol.self]
        return RcloneClient(port: 5572, session: URLSession(configuration: config))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
        let reply = Self.lock.withLock {
            Self.storedBody = body
            return Self.storedReply
        }
        let url = request.url ?? URL(string: "http://127.0.0.1")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// `item(fs:remote:)`: one entry by path through `operations/stat`.
@Suite("Item lookup", .serialized)
struct ItemLookupTests {
    @Test func returnsTheEntry() async throws {
        let client = StatURLProtocol.client(replying: #"""
        {"item": {"Path": "Photos/2022/IMG_1.HEIC", "Name": "IMG_1.HEIC", "Size": 1778129,
                  "MimeType": "image/heic", "ModTime": "2022-07-30T17:32:06Z", "IsDir": false}}
        """#)
        let item = try #require(try await client.item(fs: "cloud:", remote: "Photos/2022/IMG_1.HEIC"))
        #expect(item.path == "Photos/2022/IMG_1.HEIC")
        #expect(item.name == "IMG_1.HEIC")
        #expect(item.size == 1_778_129)
        #expect(item.isDir == false)
        #expect(item.modTime == Date(timeIntervalSince1970: 1_659_202_326))

        let body = try #require(StatURLProtocol.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["fs"] as? String == "cloud:")
        #expect(json["remote"] as? String == "Photos/2022/IMG_1.HEIC")
    }

    @Test func returnsNilForAMissingPath() async throws {
        let client = StatURLProtocol.client(replying: #"{"item": null}"#)
        #expect(try await client.item(fs: "cloud:", remote: "no/such/file") == nil)
    }
}
