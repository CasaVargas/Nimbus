import Foundation

enum TransferOutcome: Codable, Equatable, Sendable {
    case completed
    case failed(String)
    case cancelled
}

struct TransferRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// rclone's ephemeral job identifier. Restored records keep it for display
    /// parity, but only active rows may use it for RC calls.
    let jobID: Int?
    let operation: TransferOperation
    let source: String
    let destination: String
    let startedAt: Date
    let completedAt: Date
    let outcome: TransferOutcome
    let origin: TransferOrigin
}

protocol TransferHistoryPersisting: Sendable {
    func load() async throws -> [TransferRecord]
    func save(_ records: [TransferRecord]) async throws
    func quarantineCorruptFile() async
}

/// Owns the only save path. If an older disk write suspends, later terminal
/// updates replace its pending snapshot and are written immediately after it.
actor TransferHistoryWriter {
    private let history: any TransferHistoryPersisting
    private var latestSnapshot: [TransferRecord] = []
    private var isWriting = false

    init(history: any TransferHistoryPersisting) {
        self.history = history
    }

    func save(_ records: [TransferRecord]) async throws {
        latestSnapshot = records
        guard !isWriting else { return }

        isWriting = true
        defer { isWriting = false }

        while true {
            let snapshot = latestSnapshot
            try await history.save(snapshot)
            guard snapshot != latestSnapshot else { return }
        }
    }
}

enum TransferHistoryFileError: Error {
    case corrupt
    case unsupportedVersion(Int)
}

struct TransferHistoryFile: TransferHistoryPersisting {
    private struct Document: Codable {
        let version: Int
        let records: [TransferRecord]
    }

    private static let currentVersion = 1
    private let url: URL

    init(url: URL = Self.defaultURL) {
        self.url = url
    }

    func load() async throws -> [TransferRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw TransferHistoryFileError.corrupt
        }

        guard document.version == Self.currentVersion else {
            throw TransferHistoryFileError.unsupportedVersion(document.version)
        }
        return document.records
    }

    func save(_ records: [TransferRecord]) async throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(version: Self.currentVersion, records: records))
        try data.write(to: url, options: .atomic)
    }

    func quarantineCorruptFile() async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let quarantined = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(UUID().uuidString).json")
        do {
            try FileManager.default.moveItem(at: url, to: quarantined)
        } catch {
            // Leave the original untouched; the next launch can retry.
        }
    }

    private static var defaultURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupport
            .appendingPathComponent("Nimbus", isDirectory: true)
            .appendingPathComponent("transfer-history-v1.json")
    }
}

enum TransferHistoryPolicy {
    static func prune(
        _ records: [TransferRecord],
        retention: TransferHistoryRetention,
        now: Date = Date()
    ) -> [TransferRecord] {
        let maximumAge: TimeInterval?
        switch retention {
        case .sevenDays:
            maximumAge = 7 * 86_400
        case .thirtyDays:
            maximumAge = 30 * 86_400
        case .forever, .untilQuit:
            maximumAge = nil
        }

        guard let maximumAge else { return records }
        let cutoff = now.addingTimeInterval(-maximumAge)
        return records.filter { $0.completedAt >= cutoff }
    }
}
