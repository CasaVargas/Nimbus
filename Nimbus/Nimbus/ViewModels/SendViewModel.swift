import Foundation
import Observation
import RcloneKit

/// The rclone calls a send needs. A protocol so the flow can be tested
/// without a daemon.
protocol SendClient: Sendable {
    /// Names in a cloud folder; empty when the folder doesn't exist yet.
    func names(remote: String, path: String) async throws -> Set<String>
    /// Starts copying one local file; returns rclone's job id.
    func copyFile(localDirectory: String, name: String, remote: String, destinationPath: String) async throws -> Int
    /// Starts copying a local folder's contents into a cloud folder.
    func copyFolder(localPath: String, remote: String, destinationPath: String) async throws -> Int
}

struct RcloneSendClient: SendClient {
    let client: RcloneClient

    func names(remote: String, path: String) async throws -> Set<String> {
        do {
            return Set(try await client.listFiles(fs: "\(remote):", remote: path).map(\.name))
        } catch {
            // rclone copies into a folder that isn't there by creating it.
            if error.localizedDescription.lowercased().contains("directory not found") { return [] }
            throw error
        }
    }

    func copyFile(localDirectory: String, name: String, remote: String, destinationPath: String) async throws -> Int {
        try await client.copyFileAsync(
            srcFs: localDirectory, srcRemote: name, dstFs: "\(remote):", dstRemote: destinationPath
        )
    }

    func copyFolder(localPath: String, remote: String, destinationPath: String) async throws -> Int {
        try await client.copy(srcFs: localPath, dstFs: "\(remote):\(destinationPath)")
    }
}

@Observable
@MainActor
final class SendViewModel {
    let request: SendRequest
    var remote: String
    var path: String {
        didSet { if path != oldValue { clashes = [] } }
    }

    /// Names already in the destination, found by the last `send` that
    /// stopped to ask. Empty until then.
    private(set) var clashes: [String] = []
    private(set) var isWorking = false
    private(set) var error: NimbusError?

    private let client: any SendClient

    init(request: SendRequest, remoteNames: [String], lastRemote: String?, lastPath: String?, client: any SendClient) {
        self.request = request
        self.client = client
        // The last destination, when that cloud still exists.
        if let lastRemote, remoteNames.contains(lastRemote) {
            remote = lastRemote
            path = lastPath ?? ""
        } else {
            remote = remoteNames.first ?? ""
            path = ""
        }
    }

    var canSend: Bool { !remote.isEmpty && !isWorking }

    func remoteChanged() {
        path = ""
        clashes = []
        error = nil
    }

    /// Starts the copies and returns true. Returns false without copying
    /// anything when names clash and `policy` is nil (the sheet then asks),
    /// or when rclone refused.
    func send(policy: SendClashPolicy?, store: TransferStore) async -> Bool {
        guard canSend else { return false }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let existing = try await client.names(remote: remote, path: path)
            let found = SendPlan.clashes(request.items, existing: existing)
            guard found.isEmpty || policy != nil else {
                clashes = found
                return false
            }
            for step in SendPlan.steps(for: request.items, existing: existing, policy: policy ?? .replace) {
                let destination = SendPlan.destinationPath(folder: path, name: step.destinationName)
                let source = step.item.url.path
                let jobID: Int
                if step.item.isDirectory {
                    jobID = try await client.copyFolder(localPath: source, remote: remote, destinationPath: destination)
                } else {
                    jobID = try await client.copyFile(
                        localDirectory: step.item.url.deletingLastPathComponent().path,
                        name: step.item.name, remote: remote, destinationPath: destination
                    )
                }
                store.addTransfer(
                    jobId: jobID, operation: .copy, srcFs: source, dstFs: "\(remote):\(destination)",
                    origin: .sendToNimbus
                )
            }
            return true
        } catch {
            self.error = NimbusError.classify(error)
            return false
        }
    }
}
