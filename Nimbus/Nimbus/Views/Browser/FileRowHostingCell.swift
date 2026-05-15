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

    // Type-erased so configure() can inject @Observable environment objects
    // without making the cell generic. The environment pair is set once per
    // table (from FileTableRepresentable) and carried through every cell.
    private var hosting: NSHostingView<AnyView>?

    /// Environment objects required by FileRowView → CloudStatusColumn.
    /// Set by FileTableRepresentable before any reloadData() call.
    var transferStore: TransferStore?
    var fileProviderBridge: FileProviderBridge?

    func configure(file: FileItem, remote: String, isSelected: Bool) {
        let rowView = FileRowView(file: file, remote: remote, isSelected: isSelected)
        let root: AnyView
        if let ts = transferStore, let fpb = fileProviderBridge {
            root = AnyView(rowView.environment(ts).environment(fpb))
        } else {
            root = AnyView(rowView)
        }
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
    }
}
