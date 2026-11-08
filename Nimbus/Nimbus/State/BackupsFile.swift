import Foundation

protocol BackupsPersisting: Sendable {
    var fileURL: URL { get }
    func load() async throws -> [BackupJob]
    func save(_ jobs: [BackupJob]) async throws
    /// Moves a corrupt file aside and returns where it went.
    func quarantineCorruptFile() async -> URL?
}

enum BackupsFileError: Error, Equatable {
    case corrupt
    case unsupportedVersion(Int)
}

/// `~/Library/Application Support/Nimbus/backups-v1.json`: a versioned,
/// pretty-printed document. Same shape and failure handling as
/// `TransferHistoryFile`.
struct BackupsFile: BackupsPersisting {
    private struct Document: Codable {
        let version: Int
        let jobs: [BackupJob]
    }

    private struct VersionEnvelope: Decodable {
        let version: Int
    }

    static let currentVersion = 1
    let fileURL: URL

    init(url: URL = Self.defaultURL) {
        fileURL = url
    }

    func load() async throws -> [BackupJob] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = Self.decoder
        let envelope: VersionEnvelope
        do {
            envelope = try decoder.decode(VersionEnvelope.self, from: data)
        } catch {
            throw BackupsFileError.corrupt
        }
        guard envelope.version == Self.currentVersion else {
            throw BackupsFileError.unsupportedVersion(envelope.version)
        }
        do {
            return try decoder.decode(Document.self, from: data).jobs
        } catch {
            throw BackupsFileError.corrupt
        }
    }

    func save(_ jobs: [BackupJob]) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Document(version: Self.currentVersion, jobs: jobs))
        try data.write(to: fileURL, options: .atomic)
    }

    func quarantineCorruptFile() async -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let quarantined = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(UUID().uuidString).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: quarantined)
            return quarantined
        } catch {
            return nil
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nimbus", isDirectory: true)
            .appendingPathComponent("backups-v1.json")
    }
}

/// Serialises saves: if a write is in flight, the newest snapshot replaces
/// any pending one and is written right after it.
actor BackupsWriter {
    private let file: any BackupsPersisting
    private var latest: [BackupJob] = []
    private var isWriting = false

    init(file: any BackupsPersisting) {
        self.file = file
    }

    func save(_ jobs: [BackupJob]) async throws {
        latest = jobs
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }
        while true {
            let snapshot = latest
            try await file.save(snapshot)
            guard snapshot != latest else { return }
        }
    }
}
