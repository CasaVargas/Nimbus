import SwiftUI

enum TransferFilter: String, CaseIterable, Identifiable {
    case all
    case crossRemoteDrops
    case manualCopies
    case syncJobs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .crossRemoteDrops: return "Cross-remote Drops"
        case .manualCopies: return "Manual Copies"
        case .syncJobs: return "Sync Jobs"
        }
    }
}

struct TransfersView: View {
    @Environment(TransferStore.self) private var transferStore
    @State private var filter: TransferFilter = .all
    @State private var showRecent = true

    var body: some View {
        Group {
            if transferStore.transfers.isEmpty {
                EmptyState(
                    icon: "arrow.up.arrow.down",
                    title: "No Transfers",
                    message: "Cross-remote copies and syncs appear here.",
                    action: nil
                )
            } else {
                list
            }
        }
        .navigationTitle("Transfers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(TransferFilter.allCases) { f in
                            Text(verbatim: f.displayName).tag(f)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    transferStore.clearCompleted()
                } label: {
                    Label("Clear Completed", systemImage: "trash")
                }
                .disabled(filteredCompleted.isEmpty)
            }
        }
    }

    private var list: some View {
        List {
            if !filteredActive.isEmpty {
                Section {
                    ForEach(filteredActive) { transfer in
                        TransferRow(transfer: transfer)
                    }
                } header: {
                    sectionHeader("Active", count: filteredActive.count)
                }
            }
            if !filteredCompleted.isEmpty {
                Section(isExpanded: $showRecent) {
                    ForEach(Array(filteredCompleted.prefix(50))) { transfer in
                        TransferRow(transfer: transfer)
                    }
                } header: {
                    sectionHeader("Recent", count: filteredCompleted.count)
                }
            }
        }
        .listStyle(.inset)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(verbatim: title)
                .font(DesignSystem.Typography.captionEmphasized)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Spacer()
            Text(verbatim: "\(count)")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
        }
    }

    private var filteredActive: [Transfer] {
        applyFilter(transferStore.activeTransfers)
    }

    private var filteredCompleted: [Transfer] {
        applyFilter(transferStore.completedTransfers).sorted { lhs, rhs in
            (lhs.completedAt ?? lhs.startedAt) > (rhs.completedAt ?? rhs.startedAt)
        }
    }

    private func applyFilter(_ transfers: [Transfer]) -> [Transfer] {
        switch filter {
        case .all: return transfers
        case .crossRemoteDrops: return transfers.filter { $0.origin == .crossRemoteDrop }
        case .manualCopies: return transfers.filter { $0.origin == .manual && $0.operation == .copy }
        case .syncJobs: return transfers.filter { $0.operation == .sync }
        }
    }
}
