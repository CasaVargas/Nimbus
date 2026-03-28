import FileProvider
import Foundation
import UniformTypeIdentifiers
import os.log

enum RcloneError: Error, LocalizedError {
    case serverNotRunning
    case requestFailed(String)
    case invalidResponse
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .serverNotRunning: return "Rclone daemon is not running"
        case .requestFailed(let msg): return "Rclone request failed: \(msg)"
        case .invalidResponse: return "Invalid response from rclone"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }
}

class RcloneClient {

    let remoteName: String
    private let session: URLSession
    private let sharedState = SharedState()

    init(remoteName: String) {
        self.remoteName = remoteName
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Directory Listing

    func listDirectory(remotePath: String, parentIdentifier: NSFileProviderItemIdentifier) async throws -> [NSFileProviderItem] {
        let params: [String: Any] = [
            "fs": "\(remoteName):",
            "remote": remotePath,
            "opt": ["recurse": false, "noModTime": false]
        ]

        let result = try await rcCall(method: "operations/list", params: params)

        guard let list = result["list"] as? [[String: Any]] else {
            return []
        }

        return list.compactMap { entry in
            FileProviderItem.from(rcloneEntry: entry, parentIdentifier: parentIdentifier, remoteName: remoteName)
        }
    }

    /// Returns raw rclone list entries for snapshot comparison
    func listDirectoryRaw(remotePath: String) async throws -> [[String: Any]] {
        let params: [String: Any] = [
            "fs": "\(remoteName):",
            "remote": remotePath,
            "opt": ["recurse": false, "noModTime": false]
        ]

        let result = try await rcCall(method: "operations/list", params: params)
        return result["list"] as? [[String: Any]] ?? []
    }

    // MARK: - Item Fetch

    func fetchItem(identifier: NSFileProviderItemIdentifier) async throws -> FileProviderItem {
        let (dirPath, fileName) = splitPath(identifier)

        let params: [String: Any] = [
            "fs": "\(remoteName):",
            "remote": dirPath,
            "opt": ["recurse": false, "noModTime": false]
        ]

        let result = try await rcCall(method: "operations/list", params: params)
        guard let list = result["list"] as? [[String: Any]] else {
            throw RcloneError.fileNotFound(identifier.rawValue)
        }

        // Find the matching entry
        for entry in list {
            if let path = entry["Path"] as? String,
               (path as NSString).lastPathComponent == fileName {
                if let item = FileProviderItem.from(
                    rcloneEntry: entry,
                    parentIdentifier: parentIdentifier(for: identifier),
                    remoteName: remoteName
                ) {
                    return item
                }
            }
        }

        throw RcloneError.fileNotFound(identifier.rawValue)
    }

    // MARK: - Download (Materialization)

    func downloadFile(identifier: NSFileProviderItemIdentifier) async throws -> (URL, FileProviderItem) {
        let item = try await fetchItem(identifier: identifier)
        let remotePath = extractPath(from: identifier)

        // Stage in temporary directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.nimbus.fileprovider", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let localURL = tempDir.appendingPathComponent(item.filename)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: localURL)

        // Use rclone copyfile to download
        let params: [String: Any] = [
            "srcFs": "\(remoteName):",
            "srcRemote": remotePath,
            "dstFs": "/",
            "dstRemote": localURL.path,
        ]

        _ = try await rcCall(method: "operations/copyfile", params: params)

        return (localURL, item)
    }

    /// Download a file to temp directory, returning just the URL (for thumbnail generation)
    func downloadFileToTemp(identifier: NSFileProviderItemIdentifier, maxSize: Int64 = 10_485_760) async throws -> URL {
        let item = try await fetchItem(identifier: identifier)

        // Skip files larger than maxSize
        if item.fileSize > maxSize {
            throw RcloneError.requestFailed("File too large for thumbnail: \(item.fileSize) bytes")
        }

        let remotePath = extractPath(from: identifier)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.nimbus.fileprovider.thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let localURL = tempDir.appendingPathComponent(item.filename)

        try? FileManager.default.removeItem(at: localURL)

        let params: [String: Any] = [
            "srcFs": "\(remoteName):",
            "srcRemote": remotePath,
            "dstFs": "/",
            "dstRemote": localURL.path,
        ]

        _ = try await rcCall(method: "operations/copyfile", params: params)
        return localURL
    }

    // MARK: - Upload (Create/Modify)

    func createItem(basedOn template: NSFileProviderItem, contents url: URL?) async throws -> FileProviderItem {
        let parentPath: String
        if template.parentItemIdentifier == .rootContainer {
            parentPath = ""
        } else {
            parentPath = extractPath(from: template.parentItemIdentifier)
        }

        let remotePath = parentPath.isEmpty ? template.filename : "\(parentPath)/\(template.filename)"

        let isFolder = template.contentType?.conforms(to: .folder) ?? false
        if isFolder {
            let params: [String: Any] = [
                "fs": "\(remoteName):",
                "remote": remotePath,
            ]
            _ = try await rcCall(method: "operations/mkdir", params: params)
        } else if let localURL = url {
            let params: [String: Any] = [
                "srcFs": "/",
                "srcRemote": localURL.path,
                "dstFs": "\(remoteName):",
                "dstRemote": remotePath,
            ]
            _ = try await rcCall(method: "operations/copyfile", params: params)
        }

        let identifier = NSFileProviderItemIdentifier("\(remoteName):\(remotePath)")
        return FileProviderItem(
            identifier: identifier,
            parentIdentifier: template.parentItemIdentifier,
            filename: template.filename,
            isFolder: isFolder,
            fileSize: template.documentSize??.int64Value ?? 0,
            contentModificationDate: Date()
        )
    }

    func modifyItem(_ item: NSFileProviderItem, contents newContents: URL?, changedFields: NSFileProviderItemFields) async throws -> FileProviderItem {
        let remotePath = extractPath(from: item.itemIdentifier)

        // If contents changed, upload
        if changedFields.contains(.contents), let localURL = newContents {
            let params: [String: Any] = [
                "srcFs": "/",
                "srcRemote": localURL.path,
                "dstFs": "\(remoteName):",
                "dstRemote": remotePath,
            ]
            _ = try await rcCall(method: "operations/copyfile", params: params)
        }

        // If filename changed, move/rename
        if changedFields.contains(.filename) {
            let parentPath = extractPath(from: item.parentItemIdentifier)
            let newPath = parentPath.isEmpty ? item.filename : "\(parentPath)/\(item.filename)"
            let params: [String: Any] = [
                "srcFs": "\(remoteName):",
                "srcRemote": remotePath,
                "dstFs": "\(remoteName):",
                "dstRemote": newPath,
            ]
            _ = try await rcCall(method: "operations/movefile", params: params)
        }

        return FileProviderItem(
            identifier: item.itemIdentifier,
            parentIdentifier: item.parentItemIdentifier,
            filename: item.filename,
            isFolder: item.contentType?.conforms(to: .folder) ?? false,
            fileSize: item.documentSize??.int64Value ?? 0,
            contentModificationDate: Date()
        )
    }

    // MARK: - Delete

    func deleteItem(identifier: NSFileProviderItemIdentifier) async throws {
        let remotePath = extractPath(from: identifier)
        let params: [String: Any] = [
            "fs": "\(remoteName):",
            "remote": remotePath,
        ]
        _ = try await rcCall(method: "operations/deletefile", params: params)
    }

    // MARK: - RC HTTP Client

    private func rcCall(method: String, params: [String: Any]) async throws -> [String: Any] {
        var lastError: Error = RcloneError.serverNotRunning
        let maxRetries = 3
        let delays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000] // 1s, 2s, 4s

        for attempt in 0..<maxRetries {
            // Re-read port on each attempt (main app may have restarted rclone)
            guard let port = sharedState.rclonePort else {
                lastError = RcloneError.serverNotRunning
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: delays[attempt])
                }
                continue
            }

            do {
                return try await performRcCall(port: port, method: method, params: params)
            } catch {
                lastError = error
                logger.warning("rcCall attempt \(attempt + 1) failed: \(error.localizedDescription)")
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: delays[attempt])
                }
            }
        }

        throw lastError
    }

    private func performRcCall(port: UInt16, method: String, params: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: "http://127.0.0.1:\(port)/\(method)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RcloneError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw RcloneError.requestFailed(body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RcloneError.invalidResponse
        }

        return json
    }

    // MARK: - Path Helpers

    /// Extract the remote path from an identifier like "remoteName:path/to/file"
    private func extractPath(from identifier: NSFileProviderItemIdentifier) -> String {
        let raw = identifier.rawValue
        if let colonIndex = raw.firstIndex(of: ":") {
            return String(raw[raw.index(after: colonIndex)...])
        }
        return raw
    }

    /// Split identifier into (directory path, filename)
    private func splitPath(_ identifier: NSFileProviderItemIdentifier) -> (String, String) {
        let path = extractPath(from: identifier)
        let nsPath = path as NSString
        return (nsPath.deletingLastPathComponent, nsPath.lastPathComponent)
    }

    /// Get parent identifier from a child identifier
    private func parentIdentifier(for identifier: NSFileProviderItemIdentifier) -> NSFileProviderItemIdentifier {
        let path = extractPath(from: identifier)
        let parentPath = (path as NSString).deletingLastPathComponent
        if parentPath.isEmpty || parentPath == "." {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier("\(remoteName):\(parentPath)")
    }
}
