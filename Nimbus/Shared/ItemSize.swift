import Foundation

/// The size a File Provider item reports, kept apart from FileProvider types
/// so the rule can be unit-tested in the app's test target.
enum ItemSize {
    /// The `documentSize` for a file rclone listed with `listed` bytes.
    ///
    /// rclone lists a size it doesn't know as -1: Google Docs, Sheets and
    /// Slides have no size until they're exported. Passed on, the system
    /// gave the placeholder a size of Int64.max, which Finder showed and
    /// which crashed Time Machine while it sized `~/Library/CloudStorage`.
    /// `nil` is the API's "size unknown".
    static func documentSize(listed: Int64) -> Int64? {
        listed >= 0 ? listed : nil
    }

    /// Bytes appended to a file's content version.
    ///
    /// A placeholder the system already has keeps its Int64.max size when
    /// it's re-listed with an unknown size: the size only changes along with
    /// the content version. The marker changes that version once for these
    /// files (a downloaded one downloads again, a placeholder is rebuilt
    /// with no size), and stays for as long as the size is unknown. Files
    /// with a known size get nothing, so their versions don't change.
    static func contentVersionSuffix(listed: Int64) -> [UInt8] {
        documentSize(listed: listed) == nil ? [1] : []
    }
}
