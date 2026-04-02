import Foundation
import Observation

enum VFSMode: String, Codable, CaseIterable {
    case readOnly = "read-only"
    case readWrite = "read-write"
}

enum MountBackend: String, Codable, CaseIterable {
    case nfs
    case fileProvider = "fileprovider"
}

struct MountConfig: Codable, Identifiable {
    var id: String { "\(remote)-\(mountPoint)" }
    let remote: String
    let mountPoint: String
    var vfsMode: VFSMode
    var autoMount: Bool
    var backend: MountBackend
}

@Observable
final class MountConfigStore {
    private(set) var configs: [MountConfig] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let nimbus = appSupport.appendingPathComponent("Nimbus", isDirectory: true)
        try? FileManager.default.createDirectory(at: nimbus, withIntermediateDirectories: true)
        fileURL = nimbus.appendingPathComponent("mount-configs.json")
        load()
    }

    func addConfig(_ config: MountConfig) {
        configs.append(config)
        save()
    }

    func removeConfig(id: String) {
        configs.removeAll { $0.id == id }
        save()
    }

    func toggleAutoMount(id: String) {
        if let index = configs.firstIndex(where: { $0.id == id }) {
            configs[index].autoMount.toggle()
            save()
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            configs = try JSONDecoder().decode([MountConfig].self, from: data)
        } catch {
            configs = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Log but don't crash
        }
    }
}
