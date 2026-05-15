import Testing
import Foundation
@testable import Nimbus

@Suite("NimbusError")
struct NimbusErrorTests {
    @Test func classifyAuthFailedFromCommonKeywords() {
        let cases = [
            "401 Unauthorized",
            "auth required",
            "Token expired",
            "Please sign in",
            "OAuth refresh failed",
        ]
        for message in cases {
            let err = NimbusError.classify(SimpleError(message))
            #expect(err.kind == .authFailed, "expected .authFailed for: \(message)")
            #expect(err.message == message)
        }
    }

    @Test func classifyNetworkFromCommonKeywords() {
        let cases = [
            "Network connection lost",
            "Cannot reach server",
            "Connection refused",
            "You appear to be offline",
        ]
        for message in cases {
            let err = NimbusError.classify(SimpleError(message))
            #expect(err.kind == .network, "expected .network for: \(message)")
        }
    }

    @Test func classifyOtherWhenNoKeywordsMatch() {
        let err = NimbusError.classify(SimpleError("Filesystem busy"))
        #expect(err.kind == .other)
        #expect(err.message == "Filesystem busy")
    }

    @Test func equatableSameKindAndMessage() {
        let a = NimbusError(kind: .authFailed, message: "401")
        let b = NimbusError(kind: .authFailed, message: "401")
        #expect(a == b)
    }

    @Test func equatableDifferentKind() {
        let a = NimbusError(kind: .authFailed, message: "x")
        let b = NimbusError(kind: .network, message: "x")
        #expect(a != b)
    }
}

private struct SimpleError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ m: String) { message = m }
}
