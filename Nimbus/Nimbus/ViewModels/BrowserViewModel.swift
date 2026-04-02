import Foundation
import Observation
import RcloneKit

enum ViewMode: String {
    case list, grid
}

enum SortField: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case modified = "Modified"
}

@Observable
@MainActor
final class BrowserViewModel {
    private(set) var files: [FileItem] = []
    private(set) var isLoading = false
    private(set) var error: String?

    var remote: String = ""
    var path: String = ""
    var viewMode: ViewMode = .list
    var sortField: SortField = .name
    var sortAscending: Bool = true
    var selection: Set<String> = []

    private(set) var pathHistory: [String] = [""]
    private(set) var historyIndex: Int = 0

    private let client: RcloneClient
    private var cache: [String: [FileItem]] = [:]

    init(client: RcloneClient) {
        self.client = client
    }

    var sortedFiles: [FileItem] {
        let sorted = files.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }

            switch sortField {
            case .name:
                return sortAscending
                    ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .size:
                return sortAscending ? a.size < b.size : a.size > b.size
            case .modified:
                let aTime = a.modTime ?? .distantPast
                let bTime = b.modTime ?? .distantPast
                return sortAscending ? aTime < bTime : aTime > bTime
            }
        }
        return sorted
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < pathHistory.count - 1 }

    var pathComponents: [(name: String, path: String)] {
        var components: [(String, String)] = [("\(remote):", "")]
        let parts = path.split(separator: "/")
        var accumulated = ""
        for part in parts {
            accumulated += (accumulated.isEmpty ? "" : "/") + part
            components.append((String(part), accumulated))
        }
        return components
    }

    var fs: String { "\(remote):" }

    func loadFiles() async {
        let cacheKey = "\(remote):\(path)"
        if let cached = cache[cacheKey] {
            files = cached
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let result = try await client.listFiles(fs: fs, remote: path)
            files = result
            cache[cacheKey] = result
        } catch {
            self.error = error.localizedDescription
        }
    }

    func navigateTo(path newPath: String) async {
        selection = []
        path = newPath

        if historyIndex < pathHistory.count - 1 {
            pathHistory = Array(pathHistory[0...historyIndex])
        }
        pathHistory.append(newPath)
        historyIndex = pathHistory.count - 1

        await loadFiles()
    }

    func goBack() async {
        guard canGoBack else { return }
        historyIndex -= 1
        path = pathHistory[historyIndex]
        selection = []
        await loadFiles()
    }

    func goForward() async {
        guard canGoForward else { return }
        historyIndex += 1
        path = pathHistory[historyIndex]
        selection = []
        await loadFiles()
    }

    func createFolder(name: String) async throws {
        let folderPath = path.isEmpty ? name : "\(path)/\(name)"
        try await client.mkdir(fs: fs, remote: folderPath)
        await loadFiles()
    }

    func deleteItems(paths: [String]) async throws {
        for itemPath in paths {
            if let file = files.first(where: { $0.path == itemPath }) {
                if file.isDir {
                    try await client.purge(fs: fs, remote: itemPath)
                } else {
                    try await client.deleteFile(fs: fs, remote: itemPath)
                }
            }
        }
        selection = []
        await loadFiles()
    }

    func renameItem(oldPath: String, newName: String) async throws {
        let parentPath = oldPath.contains("/")
            ? String(oldPath[oldPath.startIndex..<oldPath.lastIndex(of: "/")!])
            : ""
        let newPath = parentPath.isEmpty ? newName : "\(parentPath)/\(newName)"
        try await client.moveFile(
            srcFs: fs, srcRemote: oldPath,
            dstFs: fs, dstRemote: newPath
        )
        await loadFiles()
    }
}
