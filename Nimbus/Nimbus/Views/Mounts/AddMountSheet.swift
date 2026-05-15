import SwiftUI
import AppKit

/// Add / edit a mount configuration. Same sheet handles both flows: pass
/// `editing: MountConfig?` to pre-fill state and lock the Remote picker.
///
/// Layout: SheetChrome (title + action bar) wrapping three FormSections —
/// Source (Remote), Destination (Mount Point — NFS only), Options (Backend,
/// VFS Mode, Mount-at-Launch).
struct AddMountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MountConfigStore.self) private var configStore

    var viewModel: MountsViewModel
    var editing: MountConfig?

    @State private var selectedRemote = ""
    @State private var mountPoint = ""
    @State private var vfsMode: VFSMode = .readWrite
    @State private var backend: MountBackend = .nfs
    @State private var autoMount = false
    @State private var showingFolderPicker = false

    var body: some View {
        SheetChrome(
            title: editing == nil ? "Add Mount" : "Edit Mount",
            subtitle: editing.map { LocalizedStringKey($0.remoteNameOnly) },
            body: { form },
            actions: {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Add" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        )
        .frame(minWidth: 540, minHeight: 420)
        .task {
            if let editing {
                selectedRemote = editing.remoteNameOnly
                mountPoint = editing.mountPoint
                vfsMode = editing.vfsMode
                backend = editing.backend
                autoMount = editing.autoMount
            }
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                // Folder picker returns an absolute URL; use its path directly.
                mountPoint = url.path
            case .failure:
                break
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(title: "Source", footer: nil) {
                FormRow(label: "Remote", help: nil) {
                    Picker("Remote", selection: $selectedRemote) {
                        Text("Choose…").tag("")
                        ForEach(viewModel.remoteNames, id: \.self) { name in
                            Text(verbatim: name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .disabled(editing != nil)
                    .frame(maxWidth: 240)
                }
            }
            if backend == .nfs {
                FormSection(
                    title: "Destination",
                    footer: "Local folder where the remote appears in Finder."
                ) {
                    FormRow(label: "Mount Point", help: nil) {
                        HStack(spacing: DesignSystem.Spacing.s) {
                            Text(verbatim: mountPoint.isEmpty ? "Not selected" : mountPoint)
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…") { showingFolderPicker = true }
                                .controlSize(.small)
                        }
                        .frame(maxWidth: 320, alignment: .trailing)
                    }
                }
            }
            FormSection(title: "Options", footer: nil) {
                FormRow(label: "Backend", help: nil) {
                    Picker("Backend", selection: $backend) {
                        Text("NFS").tag(MountBackend.nfs)
                        Text("File Provider").tag(MountBackend.fileProvider)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                FormRow(label: "VFS Mode", help: "How the mount handles reads and writes.") {
                    Picker("VFS Mode", selection: $vfsMode) {
                        Text("Read-only").tag(VFSMode.readOnly)
                        Text("Read-write").tag(VFSMode.readWrite)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                FormRow(label: "Mount at Launch", help: nil) {
                    Toggle("", isOn: $autoMount)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }

    private var isValid: Bool {
        guard !selectedRemote.isEmpty else { return false }
        if backend == .nfs && mountPoint.isEmpty { return false }
        return true
    }

    private func save() {
        let newConfig = MountConfig(
            remote: "\(selectedRemote):",
            mountPoint: expandTilde(mountPoint),
            vfsMode: vfsMode,
            autoMount: autoMount,
            backend: backend
        )
        if let editing {
            configStore.removeConfig(id: editing.id)
        }
        configStore.addConfig(newConfig)
        dismiss()
    }

    private func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
