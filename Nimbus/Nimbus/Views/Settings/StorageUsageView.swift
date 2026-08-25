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
            "Nimbus could not access its local sync data."
        case .notDirectory:
            "Nimbus local sync data is not a directory."
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

struct StorageUsageView: View {
    @State private var model: GeneralSettingsModel
    @State private var showingClearConfirmation = false

    init(model: GeneralSettingsModel = GeneralSettingsModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        FormSection(
            title: "Local Storage",
            footer: "Nimbus stores lightweight Finder sync data locally. Finder manages materialized cloud files separately."
        ) {
            FormRow(label: "Finder Sync Data", help: nil) {
                cacheUsageValue
            }
            FormRow(label: "Clear Sync Data", help: nil) {
                Button("Clear…", role: .destructive) {
                    showingClearConfirmation = true
                }
                .controlSize(.small)
                .disabled(!canClearCache || model.isClearingCache)
                .accessibilityLabel("Clear Finder Sync Data")
            }
        }
        .task { await model.loadCacheUsageIfNeeded() }
        .confirmationDialog(
            "Remove Nimbus sync data?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Sync Data", role: .destructive) {
                Task { await model.clearCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Finder-managed cloud files are unaffected. Nimbus rebuilds sync data as folders are enumerated.")
        }
    }

    @ViewBuilder
    private var cacheUsageValue: some View {
        switch model.cacheUsage {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Calculating Finder sync storage")
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
            .frame(maxWidth: 280, alignment: .trailing)
            .accessibilityLabel("Finder sync data unavailable: \(error)")
        }
    }

    private var canClearCache: Bool {
        if case .available(let bytes) = model.cacheUsage {
            return bytes > 0
        }
        return false
    }
}
