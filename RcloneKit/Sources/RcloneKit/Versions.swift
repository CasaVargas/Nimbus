import Foundation

/// An earlier version of a file that the service kept (S3 and B2 versioning).
///
/// rclone lists these when the remote is opened with its `versions` option
/// (`remote,versions:`): each old version shows up next to the live file as
/// `<base>-vYYYY-MM-DD-HHMMSS-mmm<ext>`, stamped with the UTC time it was
/// replaced.
public struct FileVersion: Sendable, Equatable, Identifiable {
    /// Path of the version on the versions fs, e.g. `docs/report-v2026-11-11-190948-000.txt`.
    public let path: String
    public let name: String
    /// When this version stopped being the current one.
    public let savedAt: Date
    public let size: Int64

    public var id: String { path }

    public init(path: String, name: String, savedAt: Date, size: Int64) {
        self.path = path
        self.name = name
        self.savedAt = savedAt
        self.size = size
    }

    /// The saved-at time if `name` is an old version of `file` (a file name,
    /// not a path), using rclone's naming from `lib/version`.
    public static func savedAt(name: String, file: String) -> Date? {
        let ext = goExt(file)
        let base = String(file.dropLast(ext.count))
        let prefix = base + "-v"
        guard name.hasPrefix(prefix), name.hasSuffix(ext),
              name.count == prefix.count + stampLength + ext.count else { return nil }
        let stamp = name.dropFirst(prefix.count).prefix(stampLength)
        return stampFormatter.date(from: String(stamp))
    }

    /// Go's `path.Ext`: from the last dot to the end, or "" with no dot.
    static func goExt(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return String(name[dot...])
    }

    private static let stampLength = "2006-01-02-150405-000".count

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        f.isLenient = false
        return f
    }()
}

extension RcloneClient {
    /// The same remote with old versions listed: `"r:"` → `"r,versions:"`,
    /// `"r:bucket"` → `"r,versions:bucket"`, `"r,x=1:"` → `"r,x=1,versions:"`.
    public static func versionsFs(_ fs: String) -> String {
        guard let colon = fs.firstIndex(of: ":") else { return fs + ",versions:" }
        return fs[..<colon] + ",versions" + fs[colon...]
    }

    /// Earlier versions of the file at `remote`, newest first. Lists the
    /// file's folder once; the live file itself is not included.
    public func fileVersions(fs: String, remote: String) async throws -> [FileVersion] {
        let name = (remote as NSString).lastPathComponent
        let parent = (remote as NSString).deletingLastPathComponent
        let items = try await listFiles(fs: Self.versionsFs(fs), remote: parent)
        return items
            .compactMap { item -> FileVersion? in
                guard !item.isDir, let savedAt = FileVersion.savedAt(name: item.name, file: name) else { return nil }
                return FileVersion(path: item.path, name: item.name, savedAt: savedAt, size: item.size)
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// Copy an old version to `dstFs`/`dstRemote` as an rclone job: back over
    /// the live path to restore it (the service keeps the replaced file as
    /// another version), or to a local folder to download it.
    public func copyVersionAsync(fs: String, version: FileVersion, dstFs: String, dstRemote: String) async throws -> Int {
        try await copyFileAsync(
            srcFs: Self.versionsFs(fs), srcRemote: version.path,
            dstFs: dstFs, dstRemote: dstRemote)
    }
}
