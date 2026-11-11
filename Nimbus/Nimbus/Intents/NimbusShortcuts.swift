import AppIntents

/// The actions Spotlight and the Shortcuts gallery offer without the user
/// building a shortcut.
struct NimbusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunBackupIntent(),
            phrases: [
                "Run \(\.$backup) in \(.applicationName)",
                "Back up \(\.$backup) with \(.applicationName)",
                "Run a \(.applicationName) backup",
            ],
            shortTitle: "Run Backup",
            systemImageName: "clock.arrow.circlepath")
        AppShortcut(
            intent: CopyShareLinkIntent(),
            phrases: ["Copy a \(.applicationName) share link"],
            shortTitle: "Copy Share Link",
            systemImageName: "link")
        AppShortcut(
            intent: KeepDownloadedIntent(),
            phrases: ["Keep downloaded with \(.applicationName)"],
            shortTitle: "Keep Downloaded",
            systemImageName: "arrow.down.circle")
        AppShortcut(
            intent: AllowRemovingDownloadIntent(),
            phrases: ["Allow removing download with \(.applicationName)"],
            shortTitle: "Allow Removing Download",
            systemImageName: "icloud.and.arrow.up")
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
