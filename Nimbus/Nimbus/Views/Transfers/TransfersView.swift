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
        case .crossRemoteDrops: return "Drops Between Clouds"
        case .manualCopies: return "Manual Copies"
        case .syncJobs: return "Sync Jobs"
        }
    }
}

struct TransfersView: View {
    /// When set, only transfers that read from or write to this remote are
    /// listed (the volume pane's Transfers tab).
    var remoteFilter: String? = nil
    @Environment(TransferStore.self) private var transferStore
    @Environment(RcloneDaemon.self) private var daemon
    @State private var filter: TransferFilter = .all
    @State private var showRecent = true

    var body: some View {
        Group {
            if scopedTransfers.isEmpty {
                EmptyState(
                    icon: "arrow.up.arrow.down",
                    title: remoteFilter == nil ? "No Transfers" : "No Transfers Yet",
                    message: remoteFilter == nil
                        ? "Copies between clouds appear here."
                        : "Copies and syncs that touch this volume appear here.",
                    action: nil
                )
            } else {
                VStack(spacing: 0) {
                    activityHeader
                    Divider()
                    list
                }
            }
        }
        .navigationTitle(remoteFilter ?? "Transfers")
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
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    Task { await transferStore.clearCompleted() }
                } label: {
                    Label("Clear Completed", systemImage: "trash")
                }
                .disabled(filteredCompleted.isEmpty)
            }
        }
    }

    private var activityHeader: some View {
        HStack(spacing: DesignSystem.Spacing.l) {
            metric(value: filteredActive.count, label: "Active", tint: DesignSystem.Color.semantic.statusInfo)
            Divider().frame(height: 28)
            metric(value: transferStore.completedTransfers.count, label: "Completed", tint: DesignSystem.Color.semantic.statusOK)
            Spacer()
            if !filteredActive.isEmpty {
                Label("Working in the background", systemImage: "bolt.horizontal.circle")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.l)
        .frame(minHeight: 58)
        .background(DesignSystem.Color.semantic.surfaceSubtle.opacity(0.45))
    }

    private func metric(value: Int, label: String, tint: Color) -> some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Text("\(value)")
                .font(DesignSystem.Typography.titleEmphasized)
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var list: some View {
        List {
            if !filteredActive.isEmpty {
                Section {
                    ForEach(filteredActive) { transfer in
                        TransferRow(transfer: transfer)
                            .contextMenu {
                                Button("Cancel Transfer", systemImage: "xmark.circle") {
                                    if let jobID = transfer.jobID {
                                        Task { await transferStore.stop(jobId: jobID, client: daemon.client) }
                                    }
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
                                        Task { await transferStore.remove(id: transfer.id) }
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

    private var scopedTransfers: [Transfer] {
        guard let remoteFilter else { return transferStore.transfers }
        return transferStore.transfers.filter { $0.involves(remote: remoteFilter) }
    }

    private func applyFilter(_ transfers: [Transfer]) -> [Transfer] {
        let transfers = remoteFilter.map { name in transfers.filter { $0.involves(remote: name) } } ?? transfers
        switch filter {
        case .all: return transfers
        case .crossRemoteDrops: return transfers.filter { $0.origin == .crossRemoteDrop }
        case .manualCopies: return transfers.filter { $0.origin == .manual && $0.operation == .copy }
        case .syncJobs: return transfers.filter { $0.operation == .sync }
        }
    }
}
