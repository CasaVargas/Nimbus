import SwiftUI
import RcloneKit

struct EditRemoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RcloneDaemon.self) private var daemon
    let remote: Remote
    @State private var values: [String: String] = [:]
    @State private var providers: [Provider] = []
    @State private var isSaving = false
    @State private var error: String?

    var onComplete: (() -> Void)?

    private var provider: Provider? {
        providers.first { $0.name == remote.type }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if let error {
                    Text(error).foregroundStyle(.red).padding()
                }

                if let provider {
                    ConfigForm(options: provider.options, values: $values)
                } else {
                    ProgressView("Loading...")
                }
            }
            .navigationTitle("Edit \(remote.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            values = remote.config
            do {
                providers = try await daemon.client.getProviders()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let params = values.filter { !$0.value.isEmpty }
            try await daemon.client.updateRemote(name: remote.name, parameters: params)
            onComplete?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
