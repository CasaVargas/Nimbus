import SwiftUI
import RcloneKit

struct AddRemoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RcloneDaemon.self) private var daemon
    @State private var name = ""
    @State private var selectedProvider: Provider?
    @State private var providers: [Provider] = []
    @State private var values: [String: String] = [:]
    @State private var isSaving = false
    @State private var error: String?
    @State private var searchText = ""

    var onComplete: (() -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if selectedProvider == nil {
                    providerPicker
                } else {
                    configEditor
                }
            }
            .navigationTitle(selectedProvider == nil ? "Select Provider" : "Configure \(selectedProvider!.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if selectedProvider != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(name.isEmpty || isSaving)
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            do {
                providers = try await daemon.client.getProviders()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private var filteredProviders: [Provider] {
        if searchText.isEmpty { return providers }
        return providers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var providerPicker: some View {
        List(filteredProviders, id: \.name, selection: Binding<String?>(
            get: { selectedProvider?.name },
            set: { name in
                if let name, let provider = providers.first(where: { $0.name == name }) {
                    selectedProvider = provider
                }
            }
        )) { provider in
            VStack(alignment: .leading) {
                Text(provider.name)
                    .font(.headline)
                Text(provider.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .tag(provider.name)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedProvider = provider
            }
        }
        .searchable(text: $searchText, prompt: "Search providers")
    }

    private var configEditor: some View {
        VStack {
            Form {
                TextField("Remote Name", text: $name, prompt: Text("e.g., my-s3"))

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            if let provider = selectedProvider {
                ConfigForm(options: provider.options, values: $values)
            }
        }
    }

    private func save() async {
        guard let provider = selectedProvider else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }

        do {
            let params = values.filter { !$0.value.isEmpty }
            try await daemon.client.createRemote(name: name, type: provider.name, parameters: params)
            onComplete?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
