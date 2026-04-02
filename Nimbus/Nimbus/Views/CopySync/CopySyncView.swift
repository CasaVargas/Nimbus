import SwiftUI
import RcloneKit

struct CopySyncView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var store
    @State private var viewModel: CopySyncViewModel?

    @State private var operation: TransferOperation = .copy
    @State private var srcRemote = ""
    @State private var srcPath = ""
    @State private var dstRemote = ""
    @State private var dstPath = ""
    @State private var isRunning = false
    @State private var error: String?

    var body: some View {
        Form {
            Picker("Operation", selection: $operation) {
                Text("Copy").tag(TransferOperation.copy)
                Text("Sync").tag(TransferOperation.sync)
            }
            .pickerStyle(.segmented)

            if operation == .sync {
                Text("Sync will make the destination identical to the source. Files in the destination that don't exist in the source will be deleted.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let remotes = viewModel?.remoteNames {
                PathPicker(
                    label: "Source",
                    remoteNames: remotes,
                    selectedRemote: $srcRemote,
                    path: $srcPath
                )

                PathPicker(
                    label: "Destination",
                    remoteNames: remotes,
                    selectedRemote: $dstRemote,
                    path: $dstPath
                )
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
            }

            Button(operation == .copy ? "Start Copy" : "Start Sync") {
                Task { await startOperation() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(srcRemote.isEmpty || dstRemote.isEmpty || isRunning)
        }
        .padding()
        .navigationTitle("Copy / Sync")
        .task(id: daemon.status) {
            guard daemon.status == .connected else { return }
            if viewModel == nil {
                viewModel = CopySyncViewModel(client: daemon.client)
            }
            await viewModel?.loadRemotes()
        }
    }

    private func startOperation() async {
        isRunning = true
        error = nil
        defer { isRunning = false }

        let srcFs = srcPath.isEmpty ? "\(srcRemote):" : "\(srcRemote):\(srcPath)"
        let dstFs = dstPath.isEmpty ? "\(dstRemote):" : "\(dstRemote):\(dstPath)"

        do {
            try await viewModel?.startOperation(
                operation: operation,
                srcFs: srcFs,
                dstFs: dstFs,
                store: store
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
