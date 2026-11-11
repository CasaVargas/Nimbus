import Foundation

/// Nimbus's own Finder badges (File Provider item decorations), kept apart
/// from FileProvider types so the rules can be unit-tested in the app's test
/// target. Each identifier must be declared under `NSFileProviderDecorations`
/// in the extension's Info.plist (`project.yml`); a test checks they match.
enum ItemBadges {
    /// The file's last upload failed.
    static let uploadFailed = "app.casavargas.nimbus.FileProvider.uploadFailed"
    /// Pinned with Keep Downloaded (the item itself, not a folder above it).
    static let pinned = "app.casavargas.nimbus.FileProvider.pinned"

    /// Every identifier `identifiers(pinned:uploadFailed:)` can return.
    static let all = [uploadFailed, pinned]

    /// The item's decorations. Finder shows only the first badge, so a
    /// failed upload outranks the pin.
    static func identifiers(pinned: Bool, uploadFailed: Bool) -> [String] {
        var result: [String] = []
        if uploadFailed { result.append(Self.uploadFailed) }
        if pinned { result.append(Self.pinned) }
        return result
    }

    /// Bytes appended to an item's metadata version after its content
    /// version, so a badge change reads as a metadata change. A healthy item
    /// keeps exactly the single keep-state byte it had before badges
    /// existed, so existing domains see no version churn.
    static func metadataSuffix(keepState: Int, uploadFailed: Bool) -> [UInt8] {
        var bytes = [UInt8(truncatingIfNeeded: keepState)]
        if uploadFailed { bytes.append(1) }
        return bytes
    }
}

/// When an upload error counts as a failure worth a badge.
enum UploadFailurePolicy {
    /// Cancellations are the user or the system stopping the upload, not a
    /// failure.
    static func shouldRecord(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return false }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSUserCancelledError { return false }
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return false }
        return true
    }
}
