import SwiftUI

struct PathPicker: View {
    let label: LocalizedStringKey
    let remoteNames: [String]
    @Binding var selectedRemote: String
    @Binding var path: String

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
            }
        }
    }
}

#Preview {
    VStack {
        PathPicker(
            label: "Source",
            remoteNames: ["gdrive", "s3", "local"],
            selectedRemote: .constant("gdrive"),
            path: .constant("backup/2026")
        )
        PathPicker(
            label: "Destination",
            remoteNames: ["gdrive", "s3", "local"],
            selectedRemote: .constant(""),
            path: .constant("")
        )
    }
    .padding(DesignSystem.Spacing.xl)
    .frame(width: 600)
}
