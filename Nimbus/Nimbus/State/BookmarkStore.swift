import Foundation

struct FolderBookmark: Codable, Identifiable, Sendable {
    let id: UUID
    var remoteName: String
    var path: String
    var label: String
    var order: Int

    init(remoteName: String, path: String, label: String, order: Int) {
        self.id = UUID()
        self.remoteName = remoteName
        self.path = path
        self.label = label
        self.order = order
    }
}

@Observable
@MainActor
final class BookmarkStore {
    private(set) var bookmarks: [FolderBookmark] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let nimbus = appSupport.appendingPathComponent("Nimbus", isDirectory: true)
        try? FileManager.default.createDirectory(at: nimbus, withIntermediateDirectories: true)
        fileURL = nimbus.appendingPathComponent("bookmarks.json")
        load()
    }

    func addBookmark(remoteName: String, path: String, label: String) {
        let bookmark = FolderBookmark(remoteName: remoteName, path: path, label: label, order: bookmarks.count)
        bookmarks.append(bookmark)
        save()
        syncToAppGroup()
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        for i in bookmarks.indices { bookmarks[i].order = i }
        save()
        syncToAppGroup()
    }

    func renameBookmark(id: UUID, label: String) {
        if let index = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[index].label = label
            save()
        }
    }

    func reorder(fromOffsets: IndexSet, toOffset: Int) {
        bookmarks.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for i in bookmarks.indices { bookmarks[i].order = i }
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            bookmarks = try JSONDecoder().decode([FolderBookmark].self, from: data).sorted { $0.order < $1.order }
        } catch { bookmarks = [] }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: fileURL, options: .atomic)
        } catch {}
    }

    private func syncToAppGroup() {
        guard let defaults = UserDefaults(suiteName: "group.app.casavargas.nimbus") else { return }
        let simplified = bookmarks.map { ["remote": $0.remoteName, "path": $0.path, "label": $0.label] }
        defaults.set(simplified, forKey: "bookmarks")
    }
}
