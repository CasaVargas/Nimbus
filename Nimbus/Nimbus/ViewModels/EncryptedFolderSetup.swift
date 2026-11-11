import Foundation
import Observation
import RcloneKit

/// The rclone calls "New Encrypted Folder" makes. `RcloneClient` provides
/// them; tests use a fake.
protocol EncryptedFolderClient: Sendable {
    /// Names of the direct children of `fs` (`operations/list`).
    func entryNames(fs: String) async throws -> [String]
    func mkdir(fs: String, remote: String) async throws
    func createRemote(name: String, type: String, parameters: [String: String], options: [String: Bool]) async throws
    func deleteRemote(name: String) async throws
}

extension RcloneClient: EncryptedFolderClient {
    func entryNames(fs: String) async throws -> [String] {
        try await listFiles(fs: fs, remote: "").map(\.name)
    }
}

/// Drives the "New Encrypted Folder" sheet (#68): a `crypt` remote over a
/// folder on any cloud or on this Mac. Design:
/// `docs/superpowers/specs/2026-11-11-encrypted-folder-design.md`.
///
/// The password goes into the crypt remote's section of rclone.conf,
/// obscured by rclone, with no salt (`password2`), so the password alone
/// opens the folder anywhere. Lock with Keychain (#67) encrypts it at rest.
@Observable
@MainActor
final class EncryptedFolderSetup {
    enum Phase: Equatable {
        case editing
        case creating
        /// The remote exists; the sheet runs the Finder step next.
        case created(name: String)
        case failed(String)
    }

    static let minimumPasswordLength = 10

    var folder: TransferEndpoint?
    /// nil until the user types a name; until then the name follows the folder.
    var nameDraft: String?
    var password = ""
    var confirmation = ""
    var acknowledged = false
    private(set) var phase: Phase = .editing

    let existingNames: Set<String>
    private let client: any EncryptedFolderClient

    init(client: any EncryptedFolderClient, existingNames: Set<String>) {
        self.client = client
        self.existingNames = existingNames
    }

    // MARK: - Name

    var name: String {
        get { nameDraft ?? Self.defaultName(for: folder, taken: existingNames) }
        set { nameDraft = newValue }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var nameProblem: String? {
        let trimmed = trimmedName
        if trimmed.isEmpty { return folder == nil ? nil : String(localized: "Enter a name.") }
        if existingNames.contains(trimmed) { return String(localized: "You already have a cloud with that name.") }
        if !Self.isValidRemoteName(trimmed) {
            return String(localized: "Use letters, numbers, spaces and _ . + @ - only.")
        }
        return nil
    }

    /// rclone's remote-name rule (fspath): letters, digits, `_ . + @ -` and
    /// spaces; no leading `-` or space, no trailing space.
    static func isValidRemoteName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, let last = name.unicodeScalars.last,
              first != "-", first != " ", last != " " else { return false }
        return name.unicodeScalars.allSatisfy(isAllowed)
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
            || "_.+@- ".unicodeScalars.contains(scalar)
    }

    /// `"<folder> Encrypted"`, cleaned up to rclone's rules and numbered
    /// past names already in use.
    static func defaultName(for folder: TransferEndpoint?, taken: Set<String>) -> String {
        guard let folder else { return "" }
        let cleaned = String(String.UnicodeScalarView(
            folder.displayName.unicodeScalars.map { isAllowed($0) ? $0 : " " }
        ))
        let words = cleaned.split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = words.isEmpty ? "Encrypted" : "\(words) Encrypted"
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    // MARK: - Password

    var passwordProblem: String? {
        if !password.isEmpty, password.count < Self.minimumPasswordLength {
            return String(localized: "Use at least \(Self.minimumPasswordLength) characters.")
        }
        if !confirmation.isEmpty, confirmation != password {
            return String(localized: "The passwords don't match.")
        }
        return nil
    }

    var canCreate: Bool {
        folder != nil && phase != .creating
            && nameProblem == nil && !trimmedName.isEmpty
            && password.count >= Self.minimumPasswordLength && confirmation == password
            && acknowledged
    }

    // MARK: - Create

    func create() async {
        guard canCreate, let folder else { return }
        let name = trimmedName
        phase = .creating
        do {
            let existing = try await entries(of: folder.fs)
            if existing == nil {
                try await client.mkdir(fs: folder.fs, remote: "")
            }
            try await client.createRemote(
                name: name,
                type: "crypt",
                parameters: ["remote": folder.fs, "password": password],
                options: ["obscure": true, "nonInteractive": true]
            )
            // A folder that already has entries must be one this password
            // opens: crypt hides names it can't decrypt, so a wrong password
            // would otherwise look like an empty folder.
            if let existing, !existing.isEmpty {
                let decrypted = try? await client.entryNames(fs: "\(name):")
                if decrypted?.isEmpty ?? true {
                    try? await client.deleteRemote(name: name)
                    phase = .failed(String(localized: """
                        This folder already has files, and none of them open with that password. \
                        Check the password, or choose an empty folder.
                        """))
                    return
                }
            }
            password = ""
            confirmation = ""
            phase = .created(name: name)
        } catch {
            phase = .failed(NimbusError.classify(error).message)
        }
    }

    /// Back to the form after a failure, keeping what was typed.
    func editAgain() {
        if case .failed = phase { phase = .editing }
    }

    /// The folder's entries, or nil when it doesn't exist yet.
    private func entries(of fs: String) async throws -> [String]? {
        do {
            return try await client.entryNames(fs: fs)
        } catch {
            if error.localizedDescription.lowercased().contains("directory not found") { return nil }
            throw error
        }
    }
}
