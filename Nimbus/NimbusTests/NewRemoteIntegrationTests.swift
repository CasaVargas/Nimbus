import Foundation
import Testing
@testable import Nimbus

@Suite("NewRemoteIntegration")
@MainActor
struct NewRemoteIntegrationTests {
    @Test func enabledRegistersEveryNewRemote() async {
        let domainAdder = DomainAdderSpy()
        let service = NewRemoteIntegration(domainAdder: domainAdder)

        let failures = await service.integrate(names: ["a", "b"], addToFinder: true)

        #expect(domainAdder.names == ["a", "b"])
        #expect(failures.isEmpty)
    }

    @Test func disabledRegistersNothing() async {
        let domainAdder = DomainAdderSpy()
        let service = NewRemoteIntegration(domainAdder: domainAdder)

        let failures = await service.integrate(names: ["a"], addToFinder: false)

        #expect(domainAdder.names.isEmpty)
        #expect(failures.isEmpty)
    }

    @Test func failedRegistrationDoesNotPreventLaterRemoteRegistration() async {
        let domainAdder = DomainAdderSpy(failingNames: ["a"])
        let service = NewRemoteIntegration(domainAdder: domainAdder)

        let failures = await service.integrate(names: ["a", "b"], addToFinder: true)

        #expect(domainAdder.names == ["a", "b"])
        #expect(failures == [
            RemoteIntegrationFailure(remoteName: "a", message: "Finder unavailable"),
        ])
    }
}

@MainActor
private final class DomainAdderSpy: FileProviderDomainAdding {
    private(set) var names: [String] = []
    private let failingNames: Set<String>

    init(failingNames: Set<String> = []) {
        self.failingNames = failingNames
    }

    func addDomain(identifier: String, displayName: String) async throws {
        names.append(identifier)
        if failingNames.contains(identifier) {
            throw DomainAdderError.finderUnavailable
        }
    }
}

private enum DomainAdderError: LocalizedError {
    case finderUnavailable

    var errorDescription: String? { "Finder unavailable" }
}
