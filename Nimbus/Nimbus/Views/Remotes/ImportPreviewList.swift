import SwiftUI

/// Pure-presentation list of parsed remotes for the Import Config sheet.
/// Caller owns selection set, rename map, and conflict predicate.
struct ImportPreviewList: View {
    let remotes: [ParsedRemote]
    @Binding var selected: Set<UUID>
    @Binding var renames: [UUID: String]
    let isConflict: (ParsedRemote) -> Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(remotes) { remote in
                    ImportRemoteRow(
                        remote: remote,
                        isSelected: selected.contains(remote.id),
                        isConflict: isConflict(remote),
                        rename: renameBinding(for: remote),
                        onToggle: { toggle(remote) }
                    )
                    Divider()
                        .padding(.leading, DesignSystem.Spacing.xl)
                }
            }
        }
    }

    private func toggle(_ remote: ParsedRemote) {
        if selected.contains(remote.id) {
            selected.remove(remote.id)
        } else {
            selected.insert(remote.id)
        }
    }

    private func renameBinding(for remote: ParsedRemote) -> Binding<String> {
        Binding(
            get: { renames[remote.id] ?? "" },
            set: { renames[remote.id] = $0 }
        )
    }
}
