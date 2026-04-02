import SwiftUI

struct StorageUsageView: View {
    @State private var totalCached: Int64 = 0
    @State private var isLoading = true

    var body: some View {
        GroupBox("Local Cache") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if totalCached > 0 {
                Text("\(ByteCountFormatter.string(fromByteCount: totalCached, countStyle: .file)) cached locally")
                    .foregroundStyle(.secondary)
            } else {
                Text("Cache usage information will be available when File Provider is active.")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await calculateCacheSize()
        }
    }

    private func calculateCacheSize() async {
        defer { isLoading = false }

        let result = await Task.detached(priority: .utility) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            guard let cacheURL else { return Int64(0) }

            let nimbusCache = cacheURL.appendingPathComponent("app.casavargas.nimbus.FileProvider")
            guard let enumerator = FileManager.default.enumerator(
                at: nimbusCache,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return Int64(0) }

            let allObjects = enumerator.allObjects
            var total: Int64 = 0
            for case let fileURL as URL in allObjects {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
            return total
        }.value

        totalCached = result
    }
}
