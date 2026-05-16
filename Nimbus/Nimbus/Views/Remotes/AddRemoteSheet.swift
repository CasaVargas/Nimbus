import SwiftUI
import RcloneKit

struct AddRemoteSheet: View {
    let client: RcloneClient
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var providers: [Provider] = []
    @State private var selected: Provider?
    @State private var name = ""
    @State private var values: [String: String] = [:]
    @State private var creating = false
    @State private var error: NimbusError?
    @State private var loadingProviders = true

    var body: some View {
        SheetChrome(
            title: "Add Remote",
            subtitle: selected.map { LocalizedStringKey($0.name) },
            body: {
                if loadingProviders {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let selected {
                    ConfigForm(provider: selected, name: $name, values: $values)
                } else {
                    ProviderPicker(providers: providers) { provider in
                        self.selected = provider
                    }
                }
            },
            actions: {
                if selected != nil {
                    Button("Back") {
                        selected = nil
                        name = ""
                        values = [:]
                    }
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if selected != nil {
                    Button(creating ? "Adding…" : "Add Remote") {
                        Task { await create() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || creating)
                }
            }
        )
        .frame(width: 560, height: 560)
        .task {
            do {
                providers = try await client.getProviders()
            } catch {
                self.error = NimbusError.classify(error)
            }
            loadingProviders = false
        }
        .alert(
            "Couldn't add remote",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            ),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(verbatim: err.message)
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func create() async {
        creating = true
        defer { creating = false }
        guard let selected else { return }
        do {
            try await client.createRemote(
                name: name,
                type: selected.name,
                parameters: values
            )
            onDismiss()
            dismiss()
        } catch {
            self.error = NimbusError.classify(error)
        }
    }
}
