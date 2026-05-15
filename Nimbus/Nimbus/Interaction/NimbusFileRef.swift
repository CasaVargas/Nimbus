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
        CodableRepresentation(contentType: .nimbusFileRef)
    }
}

extension UTType {
    /// Custom UTI for in-app drag-and-drop payloads. Declared `exportedAs`
    /// so SwiftUI's `Transferable` machinery recognizes it in-process.
    /// Phase 1 intentionally skips the `Info.plist` `UTExportedTypeDeclarations`
    /// block — OS-wide registration is not needed yet.
    static let nimbusFileRef = UTType(exportedAs: "app.casavargas.nimbus.fileref")
}
