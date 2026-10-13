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

    @Test func disabledDefaultKeepsNewManualRemoteOutOfReconnectRegistration() async {
        let domainAdder = DomainAdderSpy()
        let service = NewRemoteIntegration(domainAdder: domainAdder)
        let disabledDomainNames: Set<String> = ["existing"]

        let result = await service.integrate(
            names: ["manual"],
            addToFinder: false,
            disabledDomainNames: disabledDomainNames
        )

        #expect(domainAdder.names.isEmpty)
        #expect(result.failures.isEmpty)
        #expect(result.disabledDomainNames == ["existing", "manual"])
    }

    @Test func disabledDefaultKeepsEveryNewImportedRemoteOutOfReconnectRegistration() async {
        let domainAdder = DomainAdderSpy()
        let service = NewRemoteIntegration(domainAdder: domainAdder)
        let disabledDomainNames: Set<String> = ["existing"]

        let result = await service.integrate(
            names: ["imported", "renamedImport"],
            addToFinder: false,
            disabledDomainNames: disabledDomainNames
        )

        #expect(domainAdder.names.isEmpty)
        #expect(result.failures.isEmpty)
        #expect(result.disabledDomainNames == ["existing", "imported", "renamedImport"])
    }

    @Test func disabledNewRemotesPersistAndReconnectFiltersOnlyThoseRemotes() async {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        let domainAdder = DomainAdderSpy()
        let service = NewRemoteIntegration(domainAdder: domainAdder)

        let manualResult = await service.integrate(
            names: ["manual"],
            addToFinder: false,
            disabledDomainNames: settings.disabledFileProviderDomains
        )
        settings.disabledFileProviderDomains = manualResult.disabledDomainNames

        let importedResult = await service.integrate(
            names: ["renamedImport"],
            addToFinder: false,
            disabledDomainNames: settings.disabledFileProviderDomains
        )
        settings.disabledFileProviderDomains = importedResult.disabledDomainNames

        let reloadedSettings = AppSettings(defaults: defaults)
        let eligible = fileProviderReconnectEligibleRemotes(
            from: ["manual", "renamedImport", "enabled", "existing"],
            excluding: reloadedSettings.disabledFileProviderDomains
        )

        #expect(domainAdder.names.isEmpty)
        #expect(reloadedSettings.disabledFileProviderDomains == ["manual", "renamedImport"])
        #expect(eligible == ["enabled", "existing"])
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

    private func isolatedDefaults() -> UserDefaults {
        let name = "NimbusTests.NewRemoteIntegration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
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
