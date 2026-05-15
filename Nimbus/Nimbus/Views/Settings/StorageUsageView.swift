import SwiftUI

struct StorageUsageView: View {
    @State private var totalCached: Int64 = 0
    @State private var isLoading = true
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(
                title: "Local Cache",
                footer: "Cached files speed up repeated access. Clearing removes only local copies — cloud files are unaffected."
            ) {
                FormRow(label: "Used", help: nil) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(verbatim: usageText)
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    }
                }
                FormRow(label: "Clear Cache", help: nil) {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Text("Clear…")
                    }
                    .controlSize(.small)
                    .disabled(totalCached == 0)
                }
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
        .task { await recompute() }
        .confirmationDialog(
            "Remove all cached files?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Cache", role: .destructive) {
                Task { await clearCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cloud files are unaffected. Files will re-download on access.")
        }
    }

    private var usageText: String {
        if totalCached == 0 { return "Empty" }
        return ByteCountFormatter.string(fromByteCount: totalCached, countStyle: .file)
    }

    private func cacheURL() -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return caches?.appendingPathComponent("app.casavargas.nimbus.FileProvider")
    }

    private func recompute() async {
        isLoading = true
        defer { isLoading = false }
        guard let url = cacheURL() else { totalCached = 0; return }
        let result = await Task.detached(priority: .utility) {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return Int64(0) }
            var total: Int64 = 0
            for case let fileURL as URL in enumerator.allObjects {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
            return total
        }.value
        totalCached = result
    }

    private func clearCache() async {
        guard let url = cacheURL() else { return }
        try? FileManager.default.removeItem(at: url)
        await recompute()
    }
}

#Preview {
    StorageUsageView()
        .frame(width: 480, height: 320)
}
