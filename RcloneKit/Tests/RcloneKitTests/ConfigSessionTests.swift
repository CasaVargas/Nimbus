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

// This suite owns the shared config/create mock endpoint. Any test that
// POSTs to config/create — including createRemote(), moved in here from
// RemotesTests.swift — must live in this suite, or it can race a bare @Test
// free function elsewhere and dequeue a response meant for a different
// test.
//
// Every reset here is scoped to "config/create" via MockURLProtocol.reset(
// endpoint:), never the old global resetQueues(). `.serialized` only orders
// tests within THIS suite; a sibling `.serialized` suite (e.g. MockHarness
// in RcloneClientTests.swift) still runs concurrently with this one, so a
// global clear would let either suite wipe the other's queued response
// mid-test.
@Suite("ConfigSession", .serialized)
struct ConfigSessionTests {

    @Test func plainOptionBecomesQuestion() async throws {
        MockURLProtocol.reset(endpoint: "config/create")
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
        MockURLProtocol.reset(endpoint: "config/create")
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
        MockURLProtocol.reset(endpoint: "config/create")
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
        MockURLProtocol.reset(endpoint: "config/create")
        MockURLProtocol.enqueue(
            endpoint: "config/create",
            json: machineJSON(state: "", option: nil)
        )
        let step = try await makeTestClient().startConfig(name: "r", type: "s3", askAll: false)
        #expect(step == .done)
    }

    @Test func errorInsideTwoHundredThrows() async throws {
        MockURLProtocol.reset(endpoint: "config/create")
        MockURLProtocol.enqueue(
            endpoint: "config/create",
            json: #"{"Error": "couldn't fetch token: bad credentials", "Result": "", "State": "", "Option": null}"#
        )
        await #expect(throws: RcloneError.self) {
            _ = try await makeTestClient().startConfig(name: "r", type: "drive", askAll: false)
        }
    }

    @Test func continueSendsStateAndResultInsideOpt() async throws {
        MockURLProtocol.reset(endpoint: "config/create")
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

    // Moved from RemotesTests.swift (Ruling A) and strengthened to assert on
    // the captured request body (Ruling B) — race-safe here because this
    // suite is .serialized and owns config/create.
    @Test func createRemote() async throws {
        MockURLProtocol.reset(endpoint: "config/create")
        let client = makeTestClient()
        try await client.createRemote(name: "myremote", type: "s3", parameters: ["region": "us-east-1"])

        let body = try #require(MockURLProtocol.lastRequestBodies["config/create"])
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["name"] as? String == "myremote")
        #expect(json["type"] as? String == "s3")
        #expect((json["parameters"] as? [String: Any])?["region"] as? String == "us-east-1")
    }
}
