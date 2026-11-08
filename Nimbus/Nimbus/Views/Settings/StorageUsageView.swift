import Foundation
import Observation
import os
import SwiftUI

protocol LocalCacheManaging: Sendable {
    func cachedBytes() async throws -> Int64
    func clearCache() async throws
}

/// Manages only the File Provider extension's persisted sync snapshots.
/// Finder owns materialized cloud-file storage and must never be scanned or
/// removed by Nimbus.
struct FileProviderSyncCacheStore: LocalCacheManaging {
    private let snapshotDirectory: URL?

    init(snapshotDirectory: URL? = Self.defaultSnapshotDirectory) {
        self.snapshotDirectory = snapshotDirectory
    }

    func cachedBytes() async throws -> Int64 {
        guard let snapshotDirectory else { throw CacheStoreError.unavailable }

        return try await Task.detached(priority: .utility) {
            try Self.cacheSize(at: snapshotDirectory)
        }.value
    }

    func clearCache() async throws {
        guard let snapshotDirectory else { throw CacheStoreError.unavailable }

        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: snapshotDirectory.path) else { return }
            try fileManager.removeItem(at: snapshotDirectory)
        }.value
    }

    private static var defaultSnapshotDirectory: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.app.casavargas.nimbus"
        )?.appendingPathComponent("FileProviderSync", isDirectory: true)
    }

    private static func cacheSize(at cacheURL: URL) throws -> Int64 {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: cacheURL.path, isDirectory: &isDirectory) else {
            return 0
        }
        guard isDirectory.boolValue else { throw CacheStoreError.notDirectory }
        guard let enumerator = fileManager.enumerator(
            at: cacheURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CacheStoreError.unavailable
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

private enum CacheStoreError: LocalizedError {
    case unavailable
    case notDirectory

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Nimbus couldn't read its Finder change records."
        case .notDirectory:
            "Nimbus's Finder change records are in an unexpected format."
        }
    }
}

@MainActor
@Observable
final class GeneralSettingsModel {
    enum CacheUsage: Equatable {
        case loading
        case available(Int64)
        case failed(String)
    }

    private let cacheStore: any LocalCacheManaging
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "settings.cache")
    private var hasLoadedCacheUsage = false

    var cacheUsage: CacheUsage
    var clearCacheError: String?
    private(set) var isClearingCache = false

    init(
        cacheStore: any LocalCacheManaging = FileProviderSyncCacheStore(),
        cacheUsage: CacheUsage = .loading
    ) {
        self.cacheStore = cacheStore
        self.cacheUsage = cacheUsage
        hasLoadedCacheUsage = cacheUsage != .loading
    }

    func loadCacheUsageIfNeeded() async {
        guard !hasLoadedCacheUsage else { return }
        await refreshCacheUsage()
    }

    func refreshCacheUsage() async {
        hasLoadedCacheUsage = true
        cacheUsage = .loading
        do {
            cacheUsage = .available(try await cacheStore.cachedBytes())
        } catch {
            logger.error("Sync data scan failed: \(error.localizedDescription, privacy: .private)")
            cacheUsage = .failed(error.localizedDescription)
        }
    }

    func clearCache() async {
        isClearingCache = true
        clearCacheError = nil
        defer { isClearingCache = false }

        do {
            try await cacheStore.clearCache()
            await refreshCacheUsage()
        } catch {
            let message = error.localizedDescription
            logger.error("Sync data reset failed: \(message, privacy: .private)")
            cacheUsage = .failed(message)
            clearCacheError = message
        }
    }
}

/// "Finder change records": the File Provider extension's sync snapshots.
/// Not a store of downloaded files, so it sits under Troubleshooting and
/// says plainly what resetting does.
struct FinderChangeRecordsRow: View {
    @State private var model: GeneralSettingsModel
    @State private var showingResetConfirmation = false

    init(model: GeneralSettingsModel = GeneralSettingsModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        FormRow(
            label: "Finder change records",
            help: "Nimbus remembers what Finder has already seen so it only shows changes. Resetting makes Finder check every folder again. Your files aren't touched."
        ) {
            HStack(spacing: DesignSystem.Spacing.s) {
                usageValue
                Button("Reset…", role: .destructive) {
                    showingResetConfirmation = true
                }
                .controlSize(.small)
                .disabled(!canReset || model.isClearingCache)
                .accessibilityLabel("Reset Finder change records")
            }
        }
        .task { await model.loadCacheUsageIfNeeded() }
        .confirmationDialog(
            "Reset Finder change records?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task { await model.clearCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Finder checks every folder again the next time you open it. Files in your clouds and on this Mac aren't touched.")
        }
    }

    @ViewBuilder
    private var usageValue: some View {
        switch model.cacheUsage {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Measuring Finder change records")
        case .available(let bytes):
            Text(verbatim: bytes == 0 ? "Empty" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
        case .failed(let error):
            Label {
                Text(verbatim: error)
                    .lineLimit(2)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Color.semantic.statusError)
            .frame(maxWidth: 240, alignment: .trailing)
            .accessibilityLabel("Finder change records unavailable: \(error)")
        }
    }

    private var canReset: Bool {
        if case .available(let bytes) = model.cacheUsage { return bytes > 0 }
        return false
    }
}
