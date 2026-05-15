import Foundation

/// Test seam for the subset of `RcloneClient` functionality that
/// `QuickLookHost` needs. Production code uses `RcloneClientAdapter`; tests
/// substitute a stub.
protocol RcloneClientProtocol: AnyObject, Sendable {
    /// Downloads the remote file at `remote:path` to a temporary local file
    /// and returns the URL. The caller is responsible for deleting both the
    /// returned file and its parent temp directory when finished.
    func downloadToTemp(remote: String, path: String) async throws -> URL
}
