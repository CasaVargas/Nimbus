import Foundation

/// The File Provider extension's staging folder, shared by every extension
/// instance in the container's `tmp`. Each instance stages in its own
/// `<pid>/<UUID>` folder inside it, so `invalidate()` can remove one
/// instance's files without wiping other domains or sibling instances, and
/// startup can remove the folders of dead processes.
struct StagingArea: Sendable {
    /// The extension process's staging area.
    static let shared = StagingArea()

    /// `<container tmp>/app.casavargas.nimbus.FileProvider`, the folder
    /// builds before per-instance staging used, so `removeOrphans()` finds
    /// the `Downloads`/`Thumbnails` folders they left. It lives in the
    /// extension's own container, so it never needs to vary by bundle ID.
    let folder: URL

    init(containerTemp: URL = FileManager.default.temporaryDirectory) {
        folder = containerTemp.appendingPathComponent("app.casavargas.nimbus.FileProvider", isDirectory: true)
    }

    /// A new extension instance's staging folder, `<folder>/<pid>/<UUID>`:
    /// grouped by process so cleanup can remove a dead process's folder in
    /// one go, and a UUID per instance so sibling instances in the same
    /// process never collide.
    /// Callers create it when they first write.
    func makeInstanceFolder(pid: pid_t = getpid(), id: UUID = UUID()) -> URL {
        folder
            .appendingPathComponent(String(pid), isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Runs `removeOrphans()` on `shared` in the background, the first time
    /// it's called in this process: orphans come only from earlier
    /// processes, so later instances have nothing new to find.
    static func removeOrphansOnce() {
        _ = orphanCleanup
    }

    private static let orphanCleanup: Void = {
        let root = shared
        Task.detached(priority: .utility) { root.removeOrphans() }
    }()

    /// Removes the legacy shared staging folders, then the folders of dead
    /// processes, whichever domain they served. `currentPID`'s folder is
    /// untouched: its instances are alive and remove their own in
    /// `invalidate()`. Anything not named by a PID, and
    /// anything that isn't a real folder, is left alone.
    func removeOrphans(
        currentPID: pid_t = getpid(),
        isAlive: (pid_t) -> Bool = StagingArea.processIsAlive
    ) {
        let fm = FileManager.default
        try? fm.removeItem(at: folder.appendingPathComponent("Downloads", isDirectory: true))
        try? fm.removeItem(at: folder.appendingPathComponent("Thumbnails", isDirectory: true))

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else {
            return
        }
        for child in children {
            guard let pid = pid_t(child.lastPathComponent), pid > 0, pid != currentPID,
                  let values = try? child.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  !isAlive(pid) else { continue }
            try? fm.removeItem(at: child)
        }
    }

    /// True if `pid` still exists. `EPERM` means the process is alive outside
    /// this sandbox and counts as alive.
    static func processIsAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno != ESRCH
    }
}
