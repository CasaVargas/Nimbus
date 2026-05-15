import Foundation
import Observation
import RcloneKit

@Observable
@MainActor
final class MountsViewModel {
    private(set) var remoteNames: [String] = []
    private(set) var error: NimbusError?

    private let client: RcloneClient

    init(client: RcloneClient) {
        self.client = client
    }

    func loadRemotes() async {
        do {
            remoteNames = try await client.listRemotes()
        } catch {
            self.error = NimbusError.classify(error)
        }
    }
}
