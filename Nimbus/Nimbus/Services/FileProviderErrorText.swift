import FileProvider
import Foundation

/// A File Provider failure in words that are safe to log publicly: the
/// error domain and code (never `localizedDescription`, which can carry
/// paths or cloud names), plus a hint for the failure that is otherwise
/// invisible.
///
/// Why this exists: every domain call fails with
/// NSFileProviderErrorDomain -2001 when macOS doesn't recognise this copy of
/// Nimbus as the File Provider host, e.g. a build run from DerivedData on
/// another volume while no copy is installed in /Applications. Logged as
/// `<private>` at debug level, that looked like Finder cleanup silently
/// doing nothing.
enum FileProviderErrorText {
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        let base = "\(ns.domain) \(ns.code)"
        if ns.domain == NSFileProviderErrorDomain,
           ns.code == NSFileProviderError.Code.providerNotFound.rawValue {
            return base + " (provider not found: macOS doesn't recognise this copy of Nimbus as the File Provider host; run Nimbus from /Applications)"
        }
        return base
    }
}
