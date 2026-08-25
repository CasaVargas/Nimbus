import Foundation
import Observation
import os
import SwiftUI

protocol LocalCacheManaging: Sendable {
    func cachedBytes() async throws -> Int64
    func clearCache() async throws
}

struct FileProviderCacheStore: LocalCacheManaging {
    private let cacheURL: URL?

    init(cacheURL: URL? = Self.defaultCacheURL) {
        self.cacheURL = cacheURL
    }

    func cachedBytes() async throws -> Int64 {
        guard let cacheURL else { throw CacheStoreError.unavailable }

        return try await Task.detached(priority: .utility) {
            try Self.cacheSize(at: cacheURL)
        }.value
    }

    func clearCache() async throws {
        guard let cacheURL else { throw CacheStoreError.unavailable }

        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: cacheURL.path) else { return }
            try fileManager.removeItem(at: cacheURL)
        }.value
    }

    private static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("app.casavargas.nimbus.FileProvider")
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
            "Nimbus could not access the local cache."
        case .notDirectory:
            "Nimbus local cache is not a directory."
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
        cacheStore: any LocalCacheManaging = FileProviderCacheStore(),
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
            logger.error("Cache scan failed: \(error.localizedDescription, privacy: .private)")
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
            logger.error("Cache clear failed: \(error.localizedDescription, privacy: .private)")
            clearCacheError = error.localizedDescription
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
            footer: "Cached files speed up repeated access. Clearing removes only local copies; cloud files are unaffected."
        ) {
            FormRow(label: "Cached Locally", help: nil) {
                cacheUsageValue
            }
            FormRow(label: "Clear Cache", help: nil) {
                Button("Clear…", role: .destructive) {
                    showingClearConfirmation = true
                }
                .controlSize(.small)
                .disabled(!canClearCache || model.isClearingCache)
                .accessibilityLabel("Clear Cache")
            }
            if let clearCacheError = model.clearCacheError {
                Text(verbatim: clearCacheError)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.statusError)
                    .accessibilityLabel("Clear cache error: \(clearCacheError)")
            }
        }
        .task { await model.loadCacheUsageIfNeeded() }
        .confirmationDialog(
            "Remove all cached files?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Cache", role: .destructive) {
                Task { await model.clearCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cloud files are unaffected. Files will download again when accessed.")
        }
    }

    @ViewBuilder
    private var cacheUsageValue: some View {
        switch model.cacheUsage {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Calculating cached storage")
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
            .accessibilityLabel("Cache scan failed: \(error)")
        }
    }

    private var canClearCache: Bool {
        if case .available(let bytes) = model.cacheUsage {
            return bytes > 0
        }
        return false
    }
}
