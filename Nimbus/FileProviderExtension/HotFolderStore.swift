import FileProvider
import Foundation
import os

/// Persists each cloud's `RemoteChangeCadence.State` next to its snapshots
/// (`FileProviderSync/<cloud>/cadence.json`), so the scan schedule and hot
/// folders survive the extension being relaunched.
enum HotFolderStore {
    private static let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "hot-folders")
    private static let lock = NSLock()
    /// A repeat touch of the same folder inside this window, with no scan
    /// since, doesn't rewrite the file.
    private static let touchThrottle: TimeInterval = 60

    /// Marks `container` active (listed, opened from, written to).
    static func touch(remoteName: String, container: NSFileProviderItemIdentifier, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var state = load(remoteName: remoteName)
        let key = container.rawValue
        let t = now.timeIntervalSince1970
        if let last = state.activity[key], (t - last) < touchThrottle, last > (state.lastScan ?? 0) {
            return
        }
        state.touch(key, at: now)
        state.expire(at: now)
        save(state, remoteName: remoteName)
    }

    /// Marks the parent of `item` active.
    static func touchParent(remoteName: String, of item: NSFileProviderItemIdentifier) {
        let parent = PinPolicy.parentIdentifier(of: item.rawValue).map { NSFileProviderItemIdentifier($0) } ?? .rootContainer
        touch(remoteName: remoteName, container: parent)
    }

    static func state(remoteName: String) -> RemoteChangeCadence.State {
        lock.lock()
        defer { lock.unlock() }
        return load(remoteName: remoteName)
    }

    /// Records a finished scan (and drops expired activity).
    static func recordScan(remoteName: String, scope: RemoteChangeCadence.Scope, foundChanges: Bool, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var state = load(remoteName: remoteName)
        state.recordScan(scope, foundChanges: foundChanges, at: now)
        state.expire(at: now)
        save(state, remoteName: remoteName)
    }

    private static func load(remoteName: String) -> RemoteChangeCadence.State {
        guard let url = fileURL(remoteName: remoteName),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(RemoteChangeCadence.State.self, from: data) else {
            return RemoteChangeCadence.State()
        }
        return state
    }

    private static func save(_ state: RemoteChangeCadence.State, remoteName: String) {
        guard let url = fileURL(remoteName: remoteName) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            logger.warning("Failed to persist scan cadence: \(String(describing: error), privacy: .public)")
        }
    }

    private static func fileURL(remoteName: String) -> URL? {
        FileProviderRetry.appGroupContainerURL()?
            .appendingPathComponent("FileProviderSync", isDirectory: true)
            .appendingPathComponent(remoteName, isDirectory: true)
            .appendingPathComponent("cadence.json", isDirectory: false)
    }
}
