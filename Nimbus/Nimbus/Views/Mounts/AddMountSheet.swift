import SwiftUI

struct AddMountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MountConfigStore.self) private var configStore
    let remoteNames: [String]

    @State private var selectedRemote = ""
    @State private var mountPoint = ""
    @State private var vfsMode: VFSMode = .readWrite
    @State private var backend: MountBackend = .nfs
    @State private var autoMount = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Remote", selection: $selectedRemote) {
                    Text("Select...").tag("")
                    ForEach(remoteNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                TextField("Mount Point", text: $mountPoint, prompt: Text("~/CloudDrives/remote-name"))

                Picker("Mode", selection: $vfsMode) {
                    ForEach(VFSMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Backend", selection: $backend) {
                    ForEach(MountBackend.allCases, id: \.self) { b in
                        Text(b.rawValue).tag(b)
                    }
                }

                Toggle("Auto-mount on startup", isOn: $autoMount)
            }
            .navigationTitle("Add Mount")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let config = MountConfig(
                            remote: "\(selectedRemote):",
                            mountPoint: expandTilde(mountPoint),
                            vfsMode: vfsMode,
                            autoMount: autoMount,
                            backend: backend
                        )
                        configStore.addConfig(config)
                        dismiss()
                    }
                    .disabled(selectedRemote.isEmpty || mountPoint.isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
