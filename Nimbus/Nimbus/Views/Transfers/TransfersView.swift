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
    @Environment(RcloneDaemon.self) private var daemon
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
                            .contextMenu {
                                Button("Cancel Transfer", systemImage: "xmark.circle") {
                                    Task { await transferStore.stop(jobId: transfer.id, client: daemon.client) }
                                }
                            }
                    }
                } header: {
                    sectionHeader("Active", count: filteredActive.count)
                }
            }
            if !filteredCompleted.isEmpty {
                Section {
                    if showRecent {
                        ForEach(Array(filteredCompleted.prefix(50))) { transfer in
                            TransferRow(transfer: transfer)
                                .contextMenu {
                                    Button("Remove from List", systemImage: "trash") {
                                        transferStore.remove(jobId: transfer.id)
                                    }
                                }
                        }
                    }
                } header: {
                    // Custom header supplies its own disclosure — the system
                    // Section(isExpanded:) chevron doesn't render for custom
                    // headers in inset lists on macOS.
                    Button {
                        withAnimation(DesignSystem.Motion.snappy) { showRecent.toggle() }
                    } label: {
                        sectionHeader("Recent", count: filteredCompleted.count, disclosure: showRecent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.inset)
    }

    private func sectionHeader(_ title: String, count: Int, disclosure: Bool? = nil) -> some View {
        HStack {
            Text(verbatim: title)
                .font(DesignSystem.Typography.captionEmphasized)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            if let disclosure {
                Image(systemName: "chevron.right")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(disclosure ? 90 : 0))
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
            Spacer()
            Text(verbatim: "\(count)")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
        }
        .contentShape(Rectangle())
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
