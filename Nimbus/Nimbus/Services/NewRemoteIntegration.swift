import Foundation

@MainActor
protocol FileProviderDomainAdding {
    func addDomain(identifier: String, displayName: String) async throws
}

struct RemoteIntegrationFailure: Identifiable, Equatable {
    let remoteName: String
    let message: String

    var id: String { remoteName }
}

struct RemoteIntegrationResult: Equatable {
    let failures: [RemoteIntegrationFailure]
    let disabledDomainNames: Set<String>
}

@MainActor
struct NewRemoteIntegration {
    let domainAdder: any FileProviderDomainAdding

    func integrate(names: [String], addToFinder: Bool) async -> [RemoteIntegrationFailure] {
        guard addToFinder else { return [] }

        var failures: [RemoteIntegrationFailure] = []
        for name in names {
            do {
                try await domainAdder.addDomain(identifier: name, displayName: name)
            } catch {
                failures.append(
                    RemoteIntegrationFailure(remoteName: name, message: error.localizedDescription)
                )
            }
        }
        return failures
    }

    func integrate(
        names: [String],
        addToFinder: Bool,
        disabledDomainNames: Set<String>
    ) async -> RemoteIntegrationResult {
        guard addToFinder else {
            return RemoteIntegrationResult(
                failures: [],
                disabledDomainNames: disabledDomainNames.union(names)
            )
        }
        return RemoteIntegrationResult(
            failures: await integrate(names: names, addToFinder: true),
            disabledDomainNames: disabledDomainNames
        )
    }
}
