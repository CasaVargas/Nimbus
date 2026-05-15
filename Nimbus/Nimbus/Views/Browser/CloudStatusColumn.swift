import SwiftUI
import RcloneKit

/// Renders a per-row cloud-status indicator. Phase 1 (Task 8): hardcoded to `.cloud`
/// for files and `.local` for directories. Task 10 wires this to TransferStore +
/// FileProviderBridge to surface real state (downloading progress, evicted, error).
struct CloudStatusColumn: View {
    let file: FileItem

    var body: some View {
        StatusBadge(state: state)
    }

    private var state: CloudStatus {
        // Placeholder. Task 10 replaces this with real state lookup.
        file.isDir ? .local : .cloud
    }
}
