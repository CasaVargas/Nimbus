import Foundation
import Testing
import RcloneKit
@testable import Nimbus

/// Scripted stand-in for rclone: a set of existing folders with entries,
/// and the crypt remotes created over them.
final class FakeEncryptedFolderClient: EncryptedFolderClient, @unchecked Sendable {
    struct Created: Equatable {
        let name: String
        let type: String
        let parameters: [String: String]
        let options: [String: Bool]
    }

    private let lock = NSLock()
    /// fs → entries. A missing key is "directory not found".
    var folders: [String: [String]] = [:]
    /// Entries the new crypt remote shows (what decrypts with the password).
    var decrypted: [String] = []
    var createError: Error?
    private(set) var made: [String] = []
    private(set) var created: [Created] = []
    private(set) var deleted: [String] = []

    func entryNames(fs: String) async throws -> [String] {
        try lock.withLock {
            if created.contains(where: { "\($0.name):" == fs }) { return decrypted }
            guard let entries = folders[fs] else {
                throw RcloneError.requestFailed(status: 404, message: "directory not found")
            }
            return entries
        }
    }

    func mkdir(fs: String, remote: String) async throws {
        lock.withLock { made.append(fs); folders[fs] = [] }
    }

    func createRemote(name: String, type: String, parameters: [String: String], options: [String: Bool]) async throws {
        if let createError { throw createError }
        lock.withLock { created.append(.init(name: name, type: type, parameters: parameters, options: options)) }
    }

    func deleteRemote(name: String) async throws {
        lock.withLock { deleted.append(name) }
    }
}

@MainActor
struct EncryptedFolderSetupTests {
    private func filled(_ client: FakeEncryptedFolderClient,
                        folder: TransferEndpoint = .cloud(remote: "gdrive", path: "Vault"),
                        existing: Set<String> = []) -> EncryptedFolderSetup {
        let setup = EncryptedFolderSetup(client: client, existingNames: existing)
        setup.folder = folder
        setup.password = "correct horse"
        setup.confirmation = "correct horse"
        setup.acknowledged = true
        return setup
    }

    // MARK: Names

    @Test func defaultNameFollowsFolderUntilTyped() {
        let setup = EncryptedFolderSetup(client: FakeEncryptedFolderClient(), existingNames: [])
        #expect(setup.name == "")
        setup.folder = .cloud(remote: "gdrive", path: "Taxes")
        #expect(setup.name == "Taxes Encrypted")
        setup.name = "Mine"
        setup.folder = .cloud(remote: "gdrive", path: "Other")
        #expect(setup.name == "Mine")
    }

    @Test func defaultNameAtRootCleanedAndNumbered() {
        #expect(EncryptedFolderSetup.defaultName(for: .cloud(remote: "b2", path: ""), taken: []) == "b2 Encrypted")
        #expect(EncryptedFolderSetup.defaultName(for: .local(path: "/Users/x/My (Stuff)!"), taken: [])
                == "My Stuff Encrypted")
        #expect(EncryptedFolderSetup.defaultName(
            for: .cloud(remote: "b2", path: "Vault"),
            taken: ["Vault Encrypted", "Vault Encrypted 2"]) == "Vault Encrypted 3")
        #expect(EncryptedFolderSetup.defaultName(for: .local(path: "/x/(())"), taken: []) == "Encrypted")
    }

    @Test(arguments: [
        ("Vault", true), ("Vault Encrypted", true), ("a-b_c.d+e@f", true), ("é ü", true),
        ("Vault (Encrypted)", false), ("-x", false), (" x", false), ("x ", false), ("a/b", false), ("a:b", false),
    ])
    func remoteNameRules(name: String, valid: Bool) {
        #expect(EncryptedFolderSetup.isValidRemoteName(name) == valid)
    }

    @Test func nameProblems() {
        let setup = filled(FakeEncryptedFolderClient(), existing: ["gdrive", "Taken"])
        #expect(setup.nameProblem == nil)
        setup.name = "Taken"
        #expect(setup.nameProblem != nil)
        #expect(!setup.canCreate)
        setup.name = "Bad (name)"
        #expect(setup.nameProblem != nil)
        setup.name = "  "
        #expect(setup.nameProblem != nil)
        setup.name = "  Good  "
        #expect(setup.trimmedName == "Good")
        #expect(setup.canCreate)
    }

    // MARK: Password

    @Test func passwordRules() {
        let setup = filled(FakeEncryptedFolderClient())
        #expect(setup.canCreate)
        setup.password = "short"
        setup.confirmation = ""
        #expect(setup.passwordProblem != nil)
        #expect(!setup.canCreate)
        setup.password = "long enough!"
        setup.confirmation = "long enough?"
        #expect(setup.passwordProblem != nil)
        setup.confirmation = "long enough!"
        #expect(setup.passwordProblem == nil)
        #expect(setup.canCreate)
        setup.acknowledged = false
        #expect(!setup.canCreate)
    }

    @Test func needsAFolder() {
        let setup = filled(FakeEncryptedFolderClient())
        setup.folder = nil
        #expect(!setup.canCreate)
        #expect(setup.nameProblem == nil)
    }

    // MARK: Create

    @Test func createsCryptOverNewFolder() async {
        let client = FakeEncryptedFolderClient()
        let setup = filled(client)
        await setup.create()
        #expect(setup.phase == .created(name: "Vault Encrypted"))
        #expect(client.made == ["gdrive:Vault"])
        #expect(client.created == [.init(
            name: "Vault Encrypted", type: "crypt",
            parameters: ["remote": "gdrive:Vault", "password": "correct horse"],
            options: ["obscure": true, "nonInteractive": true])])
        // No salt: the password alone opens the folder.
        #expect(client.created.first?.parameters["password2"] == nil)
        #expect(setup.password.isEmpty && setup.confirmation.isEmpty)
    }

    @Test func emptyExistingFolderIsUsedAsIs() async {
        let client = FakeEncryptedFolderClient()
        client.folders["/Users/x/Vault"] = []
        let setup = filled(client, folder: .local(path: "/Users/x/Vault"))
        await setup.create()
        #expect(setup.phase == .created(name: "Vault Encrypted"))
        #expect(client.made.isEmpty)
        #expect(client.created.first?.parameters["remote"] == "/Users/x/Vault")
    }

    @Test func reconnectsFolderThePasswordOpens() async {
        let client = FakeEncryptedFolderClient()
        client.folders["gdrive:Vault"] = ["dpvsi31tdgh5tuk212aokga07k"]
        client.decrypted = ["Taxes"]
        let setup = filled(client)
        await setup.create()
        #expect(setup.phase == .created(name: "Vault Encrypted"))
        #expect(client.deleted.isEmpty)
    }

    @Test func undoesWhenNothingDecrypts() async {
        let client = FakeEncryptedFolderClient()
        client.folders["gdrive:Vault"] = ["report.pdf"]
        client.decrypted = []
        let setup = filled(client)
        await setup.create()
        guard case .failed = setup.phase else {
            Issue.record("expected failure, got \(setup.phase)")
            return
        }
        #expect(client.deleted == ["Vault Encrypted"])
        // What was typed survives for another try.
        #expect(setup.password == "correct horse")
        setup.editAgain()
        #expect(setup.phase == .editing)
        #expect(setup.canCreate)
    }

    @Test func surfacesRcloneErrors() async {
        let client = FakeEncryptedFolderClient()
        client.createError = RcloneError.requestFailed(status: 500, message: "boom")
        let setup = filled(client)
        await setup.create()
        guard case .failed(let message) = setup.phase else {
            Issue.record("expected failure, got \(setup.phase)")
            return
        }
        #expect(message.contains("boom"))
    }

    @Test func createIsANoOpWhenInvalid() async {
        let client = FakeEncryptedFolderClient()
        let setup = filled(client)
        setup.acknowledged = false
        await setup.create()
        #expect(setup.phase == .editing)
        #expect(client.created.isEmpty)
    }
}

@MainActor
struct EncryptedFolderSheetSnapshotTests {
    private func settings() -> AppSettings {
        let name = "NimbusTests.EncryptedFolder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set("/opt/homebrew/bin/rclone", forKey: "rcloneBinaryPath")
        return AppSettings(defaults: defaults)
    }

    private func render(_ setup: EncryptedFolderSetup, state: ConfigEncryptionState, named name: String) throws {
        try SnapshotHelpers.assertHostedSnapshot(
            EncryptedFolderSheet(
                client: RcloneClient(port: 5999),
                remoteNames: ["gdrive", "b2"],
                setup: setup,
                encryption: ConfigEncryptionModel(state: state, readsLiveState: false),
                onDismiss: {}
            )
            .environment(settings())
            .environment(FileProviderBridge()),
            size: CGSize(width: 560, height: 620),
            named: name
        )
    }

    @Test func rendersEmpty() throws {
        let setup = EncryptedFolderSetup(client: FakeEncryptedFolderClient(), existingNames: ["gdrive", "b2"])
        try render(setup, state: .locked, named: "EncryptedFolder-empty")
    }

    @Test func rendersFilledWithKeychainNote() throws {
        let setup = EncryptedFolderSetup(client: FakeEncryptedFolderClient(), existingNames: ["gdrive", "b2"])
        setup.folder = .cloud(remote: "gdrive", path: "Taxes")
        setup.password = "correct horse"
        setup.confirmation = "correct horsf"
        try render(setup, state: .plain, named: "EncryptedFolder-filled-plain")
    }

    @Test func rendersWrongPassword() async throws {
        let client = FakeEncryptedFolderClient()
        client.folders["gdrive:Taxes"] = ["report.pdf"]
        let setup = EncryptedFolderSetup(client: client, existingNames: [])
        setup.folder = .cloud(remote: "gdrive", path: "Taxes")
        setup.password = "correct horse"
        setup.confirmation = "correct horse"
        setup.acknowledged = true
        await setup.create()
        try render(setup, state: .locked, named: "EncryptedFolder-wrong-password")
    }
}
