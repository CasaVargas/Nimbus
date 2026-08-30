import Foundation
import Testing
@testable import RcloneKit

@Test func listRemotes() async throws {
    let client = makeTestClient()
    let remotes = try await client.listRemotes()
    #expect(remotes == ["gdrive", "s3", "dropbox"])
}

@Test func configDump() async throws {
    let client = makeTestClient()
    let dump = try await client.configDump()
    #expect(dump["gdrive"]?["type"] == "drive")
    #expect(dump["s3"]?["region"] == "us-east-1")
}

@Test func getProviders() async throws {
    let client = makeTestClient()
    let providers = try await client.getProviders()
    #expect(providers.count == 1)
    #expect(providers[0].name == "s3")
}

// createRemote() lives in ConfigSessionTests.swift's ConfigSession suite —
// it POSTs to config/create, which that suite owns to avoid racing
// MockURLProtocol's shared response queues.

@Test func deleteRemote() async throws {
    let client = makeTestClient()
    try await client.deleteRemote(name: "oldremote")
}
