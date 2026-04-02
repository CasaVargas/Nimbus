import SwiftUI
import RcloneKit

struct PathPicker: View {
    let label: String
    let remoteNames: [String]
    @Binding var selectedRemote: String
    @Binding var path: String

    var body: some View {
        GroupBox(label) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Remote", selection: $selectedRemote) {
                    Text("Select...").tag("")
                    ForEach(remoteNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                TextField("Path", text: $path, prompt: Text("e.g., documents/photos"))
            }
            .padding(8)
        }
    }
}
