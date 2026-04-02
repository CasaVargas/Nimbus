import SwiftUI
import RcloneKit

struct TransfersView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var store
    @State private var viewModel: TransfersViewModel?

    var body: some View {
        Group {
            if store.transfers.isEmpty {
                ContentUnavailableView(
                    "No Transfers",
                    systemImage: "arrow.up.arrow.down",
                    description: Text("Copy or sync operations will appear here.")
                )
            } else {
                List {
                    if !store.activeTransfers.isEmpty {
                        Section("Active") {
                            ForEach(store.activeTransfers) { transfer in
                                TransferRow(transfer: transfer) {
                                    Task {
                                        await viewModel?.cancelJob(id: transfer.id)
                                        store.cancelTransfer(jobId: transfer.id)
                                    }
                                }
                            }
                        }
                    }

                    if !store.completedTransfers.isEmpty {
                        Section("Completed") {
                            ForEach(store.completedTransfers) { transfer in
                                TransferRow(transfer: transfer, onCancel: {})
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Transfers")
        .toolbar {
            if !store.completedTransfers.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear Completed") {
                        store.clearCompleted()
                    }
                }
            }
        }
        .task(id: daemon.status) {
            guard daemon.status == .connected else { return }
            if viewModel == nil {
                let vm = TransfersViewModel(client: daemon.client)
                viewModel = vm
                vm.startStatsPolling()
            }
        }
        .onDisappear {
            viewModel?.stopStatsPolling()
        }
    }
}
