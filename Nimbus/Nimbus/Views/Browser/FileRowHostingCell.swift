import AppKit
import SwiftUI
import RcloneKit

/// NSTableView cell that hosts the SwiftUI `FileRowView` via NSHostingView.
/// Reused across rows; `prepareForReuse` tears down the hosting view so the
/// embedded `CloudStatusColumn` async .task is cancelled (SwiftUI cancels a
/// view's tasks when the view leaves the hierarchy) before the cell is
/// reconfigured for a different row — preventing a stale materialization
/// badge from a recycled cell.
final class FileRowHostingCell: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FileRowHostingCell")

    /// Concrete wrapper so the cell stays non-generic and AnyView-free while
    /// still injecting the @Observable environment pair FileRowView →
    /// CloudStatusColumn requires. `.environment(T?)` with nil is a no-op,
    /// matching the previous bare-row behavior.
    private struct FileRowHost: View {
        let file: FileItem
        let remote: String
        let isSelected: Bool
        let isEmphasized: Bool
        let transferStore: TransferStore?
        let fileProviderBridge: FileProviderBridge?
        var body: some View {
            FileRowView(file: file, remote: remote, isSelected: isSelected,
                        isEmphasized: isEmphasized)
                .environment(transferStore)
                .environment(fileProviderBridge)
        }
    }

    private var hosting: NSHostingView<FileRowHost>?

    /// Environment objects required by FileRowView → CloudStatusColumn.
    /// Set by FileTableCoordinator before configure() / any reloadData().
    var transferStore: TransferStore?
    var fileProviderBridge: FileProviderBridge?

    /// Last configuration, kept so `backgroundStyle` changes (selection
    /// emphasis flipping with window key state) can re-render the row with
    /// the correct text inversion without a full table reload.
    private var lastConfig: (file: FileItem, remote: String, isSelected: Bool)?

    /// NSTableRowView sets `.emphasized` on its cells when the selection is
    /// drawn vibrant (key window + focused table). That's the only state in
    /// which FileRowView may invert its text to white.
    ///
    /// The re-render MUST be deferred: AppKit assigns `backgroundStyle`
    /// during the row's layout pass, and mutating `rootView` there re-enters
    /// layout ("not legal to call -layoutSubtreeIfNeeded…") and can livelock
    /// the whole window. One runloop hop breaks the cycle; configure() is
    /// idempotent so coalesced dispatches are harmless.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            guard oldValue != backgroundStyle, lastConfig != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let c = self.lastConfig else { return }
                self.configure(file: c.file, remote: c.remote, isSelected: c.isSelected)
            }
        }
    }

    func configure(file: FileItem, remote: String, isSelected: Bool) {
        assert(transferStore != nil && fileProviderBridge != nil,
               "FileRowHostingCell.configure called without env objects — FileTableCoordinator must set transferStore/fileProviderBridge first")
        lastConfig = (file, remote, isSelected)
        let root = FileRowHost(
            file: file, remote: remote, isSelected: isSelected,
            isEmphasized: backgroundStyle == .emphasized,
            transferStore: transferStore, fileProviderBridge: fileProviderBridge
        )
        if let hosting {
            hosting.rootView = root
        } else {
            let h = NSHostingView(rootView: root)
            h.translatesAutoresizingMaskIntoConstraints = false
            addSubview(h)
            NSLayoutConstraint.activate([
                h.leadingAnchor.constraint(equalTo: leadingAnchor),
                h.trailingAnchor.constraint(equalTo: trailingAnchor),
                h.topAnchor.constraint(equalTo: topAnchor),
                h.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            hosting = h
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Remove the hosting view so SwiftUI tears down FileRowView and
        // cancels CloudStatusColumn's in-flight .task. configure(...) on the
        // next use rebuilds it fresh with the new (remote, path) task id.
        hosting?.removeFromSuperview()
        hosting = nil
        lastConfig = nil
    }
}
