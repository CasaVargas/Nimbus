import Foundation
import RcloneKit

/// Which clouds can list the earlier versions their service keeps.
///
/// rclone 1.76 lists old versions only on `s3`, `b2` and `imagekit` (their
/// `versions` option); Drive and OneDrive keep revisions rclone can't read.
/// ImageKit is left out (untested, a media CDN). The check is on the cloud's
/// own backend type, not the alias-resolved one: the `,versions` override
/// reaches only the named remote's backend. See
/// `docs/superpowers/specs/2026-11-11-service-versions-design.md`.
enum VersionSupport {
    private static let backends: Set<String> = ["s3", "b2"]

    static func supports(backendType: String?) -> Bool {
        backendType.map(backends.contains) ?? false
    }

    /// The inspector's Version History row: files only, supported clouds only.
    static func showsHistory(for file: FileItem, backendType: String?) -> Bool {
        !file.isDir && supports(backendType: backendType)
    }

    /// Name for a downloaded version: `report (2026-11-11 14.09).txt`, in
    /// local time. Dots, not colons: Finder shows a colon as a slash.
    static func downloadName(for fileName: String, savedAt: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH.mm"
        let ext = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        let stamped = "\(base) (\(f.string(from: savedAt)))"
        return ext.isEmpty ? stamped : "\(stamped).\(ext)"
    }
}
