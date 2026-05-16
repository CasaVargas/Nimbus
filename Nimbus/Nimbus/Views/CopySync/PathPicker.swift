import SwiftUI
import RcloneKit

struct PathPicker: View {
    let label: LocalizedStringKey
    let remoteNames: [String]
    let client: RcloneClient
    @Binding var selectedRemote: String
    @Binding var path: String

    @State private var isBrowsing = false

    var body: some View {
        FormRow(label: label, help: nil) {
            HStack(spacing: DesignSystem.Spacing.s) {
                Picker("", selection: $selectedRemote) {
                    Text("Choose…").tag("")
                    ForEach(remoteNames, id: \.self) { name in
                        Text(verbatim: name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                TextField("/", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .disabled(selectedRemote.isEmpty)

                Button {
                    isBrowsing = true
                } label: {
                    Image(systemName: "folder")
                }
                .help("Browse folders")
                .disabled(selectedRemote.isEmpty)
            }
        }
        .sheet(isPresented: $isBrowsing) {
            FolderBrowserSheet(
                remote: selectedRemote,
                client: client,
                onSelect: { chosen in path = chosen }
            )
        }
    }
}

#Preview {
    VStack {
        PathPicker(
            label: "Source",
            remoteNames: ["gdrive", "s3", "local"],
            client: RcloneClient(),
            selectedRemote: .constant("gdrive"),
            path: .constant("backup/2026")
        )
        PathPicker(
            label: "Destination",
            remoteNames: ["gdrive", "s3", "local"],
            client: RcloneClient(),
            selectedRemote: .constant(""),
            path: .constant("")
        )
    }
    .padding(DesignSystem.Spacing.xl)
    .frame(width: 600)
}
