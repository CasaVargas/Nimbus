import Foundation

/// Why a Shortcuts action couldn't run, in the sentence Shortcuts shows.
enum ShortcutError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case notRunning
    case engineNotReady
    case backupsNotLoaded
    case backup(BackupRunner.Refusal)
    case noFile
    case notInCloud(name: String)
    case topFolder
    case cannotShare(cloud: String)
    case noLink
    case service(String)

    var message: String {
        switch self {
        case .notRunning:
            "Nimbus isn't ready yet. Open Nimbus and try again."
        case .engineNotReady:
            "Nimbus couldn't start its rclone engine. Open Nimbus to see what's wrong."
        case .backupsNotLoaded:
            "Nimbus couldn't read your backups. Open Backups in Nimbus to see what's wrong."
        case .backup(.notApproved):
            "Preview this backup once in Nimbus before it can run."
        case .backup(.alreadyQueuedOrRunning):
            "This backup is already running."
        case .backup(.storeReadOnly):
            "Your backups were saved by a newer Nimbus, so this one can't run them."
        case .backup(.daemonNotConnected):
            "Nimbus couldn't start its rclone engine. Open Nimbus to see what's wrong."
        case .backup(.unknownJob):
            "That backup no longer exists."
        case .noFile:
            "Choose a file or folder in one of your clouds in Finder."
        case .notInCloud(let name):
            "“\(name)” isn't in a Nimbus cloud in Finder."
        case .topFolder:
            "Choose a file or folder inside the cloud, not the cloud itself."
        case .cannotShare(let cloud):
            "\(cloud)'s service doesn't make share links."
        case .noLink:
            "The service didn't return a link."
        case .service(let text):
            text
        }
    }

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}
