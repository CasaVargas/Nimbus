import Foundation

/// Pure rules and per-domain state storage for remotes whose top-level
/// entries are fixed (cannot be created, renamed, moved, or deleted, while
/// contents inside those folders remain writable).
///
/// Lives in `Shared/` (Foundation only) so both the app and the File Provider
/// extension share one implementation and `NimbusTests` can unit-test it.
enum FixedTopLevelPolicy {
    /// True when `path` refers to a direct child of the remote root
    /// (non-empty and containing no `/`).
    static func isTopLevelPath(_ path: String) -> Bool {
        !path.isEmpty && !path.contains("/")
    }

    /// Metadata version for `.rootContainer`: `0` for an ordinary writable
    /// root, `1` for a read-only root with fixed top-level entries. A
    /// different byte makes File Provider re-read root capabilities and flags.
    static func rootMetadataVersion(hasFixedTopLevel: Bool) -> Data {
        Data([hasFixedTopLevel ? 1 : 0])
    }

    /// Extra byte appended to a top-level folder's metadata version when
    /// protected, so File Provider re-reads its capabilities when the flag
    /// changes. Ordinary folders and all files get `[]` (byte-identical to
    /// before, no version churn). Uses `2` so it never collides with
    /// `ItemBadges.metadataSuffix`'s `uploadFailed` byte (`1`).
    static func childMetadataSuffix(isDir: Bool, isTopLevel: Bool, hasFixedTopLevel: Bool) -> [UInt8] {
        (isDir && isTopLevel && hasFixedTopLevel) ? [2] : []
    }

    /// Whether the working-set enumerator should re-report the root (and its
    /// top-level folders) because the remote's fixed-top-level state changed
    /// since it was last reported. An unreported remote defaults to `false`
    /// so ordinary remotes never churn on first pass.
    static func shouldReportRootChange(current: Bool, lastReported: Bool?) -> Bool {
        current != (lastReported ?? false)
    }

    // MARK: - Per-domain reported state

    /// Stored alongside the domain's snapshots and cadence under
    /// `<appGroup>/FileProviderSync/<remote>/reported-fixed-top-level`.
    static func reportedStateURL(remoteName: String, base: URL) -> URL {
        base
            .appendingPathComponent("FileProviderSync", isDirectory: true)
            .appendingPathComponent(remoteName, isDirectory: true)
            .appendingPathComponent("reported-fixed-top-level", isDirectory: false)
    }

    static func readReportedState(remoteName: String, base: URL) -> Bool? {
        let url = reportedStateURL(remoteName: remoteName, base: base)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "1", "true": return true
        case "0", "false": return false
        default: return nil
        }
    }

    @discardableResult
    static func writeReportedState(_ value: Bool, remoteName: String, base: URL) -> Bool {
        let url = reportedStateURL(remoteName: remoteName, base: base)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (value ? "1" : "0").write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    static func clearReportedState(remoteName: String, base: URL) {
        let url = reportedStateURL(remoteName: remoteName, base: base)
        try? FileManager.default.removeItem(at: url)
    }
}
