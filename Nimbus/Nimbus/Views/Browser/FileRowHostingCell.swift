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

    private var hosting: NSHostingView<FileRowView>?

    func configure(file: FileItem, remote: String, isSelected: Bool) {
        let root = FileRowView(file: file, remote: remote, isSelected: isSelected)
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
