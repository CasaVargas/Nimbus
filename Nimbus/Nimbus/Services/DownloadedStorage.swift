import Foundation
import Observation
import os

/// Space taken on this Mac by files downloaded into Nimbus's Finder drives,
/// and removing those downloads (spec: 2026-11-14-dock-idle-storage-design.md).
enum DownloadedStorage {
    /// Bytes of downloaded files. Folders carry no bytes of their own.
    static func totalBytes(_ entries: [MaterializedEntry]) -> Int64 {
        entries.lazy.filter { !$0.isFolder }.reduce(0) { $0 + max(0, $1.size) }
    }

    static func fileCount(_ entries: [MaterializedEntry]) -> Int {
        entries.lazy.filter { !$0.isFolder }.count
    }

    /// The files to evict: every downloaded file except those the user
    /// keeps downloaded, directly or through a kept folder (evicting those
    /// would only download them again).
    static func evictionPlan(_ entries: [MaterializedEntry], pinned: Set<String>) -> [String] {
        let folderPrefixes = pinned.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        return entries.compactMap { entry in
            guard !entry.isFolder, !pinned.contains(entry.identifier) else { return nil }
            if folderPrefixes.contains(where: { entry.identifier.hasPrefix($0) }) { return nil }
            return entry.identifier
        }
    }
}

@MainActor
@Observable
final class DownloadedStorageModel {
    struct Drive: Identifiable, Equatable {
        var remote: String
        var bytes: Int64
        var fileCount: Int
        /// Files that weren't removed last time (open, unsynced, or kept).
        var keptCount: Int = 0
        var id: String { remote }
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded
    }

    struct Source {
        var domains: () async -> [String]
        var entries: (String) async -> [MaterializedEntry]
        var pins: (String) -> Set<String>
        /// Returns how many items the system refused to evict.
        var evict: (String, [String]) async -> Int
    }

    private(set) var drives: [Drive] = []
    private(set) var state: State = .idle
    private(set) var removing: Set<String> = []
    @ObservationIgnored private let source: Source

    init(source: Source) {
        self.source = source
    }

    var totalBytes: Int64 { drives.reduce(0) { $0 + $1.bytes } }
    var isRemoving: Bool { !removing.isEmpty }

    func load() async {
        state = .loading
        var result: [Drive] = []
        for remote in await source.domains().sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let entries = await source.entries(remote)
            let kept = drives.first { $0.remote == remote }?.keptCount ?? 0
            result.append(Drive(remote: remote, bytes: DownloadedStorage.totalBytes(entries),
                                fileCount: DownloadedStorage.fileCount(entries), keptCount: kept))
        }
        drives = result
        state = .loaded
    }

    func removeDownloads(remote: String) async {
        guard !removing.contains(remote) else { return }
        removing.insert(remote)
        defer { removing.remove(remote) }
        let entries = await source.entries(remote)
        let plan = DownloadedStorage.evictionPlan(entries, pinned: source.pins(remote))
        let refused = await source.evict(remote, plan)
        let kept = DownloadedStorage.fileCount(entries) - plan.count + refused
        await reload(remote: remote, keptCount: kept)
    }

    func removeAllDownloads() async {
        for drive in drives where drive.fileCount > 0 {
            await removeDownloads(remote: drive.remote)
        }
    }

    private func reload(remote: String, keptCount: Int) async {
        let entries = await source.entries(remote)
        guard let index = drives.firstIndex(where: { $0.remote == remote }) else { return }
        drives[index] = Drive(remote: remote, bytes: DownloadedStorage.totalBytes(entries),
                              fileCount: DownloadedStorage.fileCount(entries), keptCount: keptCount)
    }
}

extension DownloadedStorageModel.Source {
    @MainActor
    static func live(bridge: FileProviderBridge) -> Self {
        Self(
            domains: { (try? await bridge.listDomains().map(\.identifier)) ?? [] },
            entries: { await bridge.materializedEntries(remote: $0) },
            pins: { PinStore.shared?.pins(domain: $0) ?? [] },
            evict: { await bridge.evict(remote: $0, identifiers: $1) }
        )
    }
}
