import Foundation

/// Throwaway `UserDefaults` for tests, kept out of `~/Library/Preferences`.
///
/// A suite named `NimbusTests.Foo.<UUID>` leaves a plist in
/// `~/Library/Preferences` for good: `removePersistentDomain(forName:)` only
/// empties it, and deleting the file races cfprefsd, which writes it back.
/// A suite named by an absolute path is stored at that path instead, so these
/// live in a per-run folder under the temporary directory.
enum ScratchDefaults {
    /// Fresh, empty defaults. `label` only names the file, for debugging.
    static func make(_ label: String) -> UserDefaults {
        let name = runDirectory.appendingPathComponent("\(label).\(UUID().uuidString)").path
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NimbusTests.Defaults", isDirectory: true)

    /// One folder per test process. Creating it also clears folders left by
    /// runs that ended over a day ago; newer ones may belong to a parallel
    /// test runner that is still using them.
    private static let runDirectory: URL = {
        let fileManager = FileManager.default
        let cutoff = Date().addingTimeInterval(-86_400)
        let earlier = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for directory in earlier {
            let modified = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: directory)
            }
        }

        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
}
