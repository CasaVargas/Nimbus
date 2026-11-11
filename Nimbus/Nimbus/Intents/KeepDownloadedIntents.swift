import AppIntents
import Foundation
import UniformTypeIdentifiers

/// **Keep Downloaded**: the same as Finder's action and the inspector's
/// switch.
struct KeepDownloadedIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Downloaded"
    static let description = IntentDescription(
        "Keeps files or folders in your clouds downloaded on this Mac, so they open offline.",
        categoryName: "Offline")

    @Parameter(title: "Files", supportedContentTypes: [.item])
    var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Keep \(\.$files) downloaded")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = try await KeepDownloadedSupport.set(true, files: files)
        return .result(dialog: "\(KeepDownloadedSupport.message(keep: true, count: count))")
    }
}

/// **Allow Removing Download**: undoes Keep Downloaded; macOS may then free
/// the space when it needs to.
struct AllowRemovingDownloadIntent: AppIntent {
    static let title: LocalizedStringResource = "Allow Removing Download"
    static let description = IntentDescription(
        "Lets macOS remove the downloaded copies of files or folders in your clouds when it needs space.",
        categoryName: "Offline")

    @Parameter(title: "Files", supportedContentTypes: [.item])
    var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Allow removing download of \(\.$files)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = try await KeepDownloadedSupport.set(false, files: files)
        return .result(dialog: "\(KeepDownloadedSupport.message(keep: false, count: count))")
    }
}

enum KeepDownloadedSupport {
    /// Resolves every file first, so one file outside Nimbus changes nothing.
    @MainActor
    static func set(_ keep: Bool, files: [IntentFile]) async throws -> Int {
        guard !files.isEmpty else { throw ShortcutError.noFile }
        var targets: [ShortcutTarget] = []
        for file in files {
            guard let url = file.fileURL else { throw ShortcutError.noFile }
            targets.append(try await ShortcutTarget.resolve(url))
        }
        let bridge = try IntentServices.require().fileProviderBridge
        for target in targets {
            do {
                try await bridge.setKeepDownloaded(keep, remote: target.remote, path: target.path)
            } catch {
                throw ShortcutError.service("Couldn't change “\((target.path as NSString).lastPathComponent)”: \(error.localizedDescription)")
            }
        }
        return targets.count
    }

    static func message(keep: Bool, count: Int) -> String {
        let items = count == 1 ? "1 item" : "\(count) items"
        return keep ? "Keeping \(items) downloaded." : "macOS may now remove the download of \(items)."
    }
}
