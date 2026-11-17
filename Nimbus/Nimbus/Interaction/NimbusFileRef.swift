import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A typed payload describing a file (or folder) reference that originated
/// inside Nimbus. Used for SwiftUI `Transferable` drag-and-drop so the
/// `DragDropCoordinator` can distinguish in-app drags from generic Finder
/// drags and route them through the rclone RC API directly instead of
/// materializing bytes locally.
struct NimbusFileRef: Codable, Hashable, Sendable, Transferable {
    let remoteName: String
    let path: String
    let size: Int64
    let isDir: Bool

    static var transferRepresentation: some TransferRepresentation {
        // Encode via JSON over a system-registered UTI so SwiftUI's drag-and-drop
        // round-trip matches without requiring UTExportedTypeDeclarations in Info.plist.
        // Drops are typed on `NimbusFileRef.self` at the destination, so non-NimbusFileRef
        // JSON drops will fail decoding and the closure won't fire.
        CodableRepresentation(contentType: .json)
    }
}

/// Multi-file drag payload. SwiftUI Table's `.draggable` on a cell produces only
/// the directly-dragged row's Transferable, not the entire selection. To support
/// multi-row drag we wrap the selection set into a bundle and treat it as a single
/// Transferable. Sources produce a bundle containing all selected files (when the
/// dragged row is part of the selection) or just the dragged file.
struct NimbusFileBundle: Codable, Hashable, Sendable, Transferable {
    let refs: [NimbusFileRef]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// Anything the browser accepts as a drop: a drag that started inside Nimbus,
/// or files and folders dragged in from Finder (or any other app).
enum BrowserDrop: Sendable, Transferable {
    case bundle(NimbusFileBundle)
    case file(URL)

    static var transferRepresentation: some TransferRepresentation {
        // File URLs first: a .json file dragged from Finder is a file to
        // upload, not a Nimbus payload to decode.
        ProxyRepresentation(importing: { (url: URL) in BrowserDrop.file(url) })
        DataRepresentation(importedContentType: .json) { data in
            .bundle(try JSONDecoder().decode(NimbusFileBundle.self, from: data))
        }
    }

    /// Splits a drop into in-app references and local file URLs.
    static func split(_ drops: [BrowserDrop]) -> (refs: [NimbusFileRef], urls: [URL]) {
        var refs: [NimbusFileRef] = []
        var urls: [URL] = []
        for drop in drops {
            switch drop {
            case .bundle(let bundle): refs += bundle.refs
            case .file(let url) where url.isFileURL: urls.append(url)
            case .file: break
            }
        }
        return (refs, urls)
    }
}
