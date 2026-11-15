import AppKit
import UniformTypeIdentifiers

/// "Nimbus" in other apps' Share menus. Deliberately thin: it records what
/// was shared in the app group container (`ShareInbox`), opens Nimbus on it
/// and finishes. Choosing the cloud and folder, and the upload itself,
/// happen in the app, where transfers are visible.
final class ShareViewController: NSViewController {
    private let label = NSTextField(labelWithString: "Opening Nimbus…")

    override func loadView() {
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.preferredMaxLayoutWidth = 280
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 90))
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
        ])
        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { await handOff() }
    }

    /// What one shared attachment turned out to be, in a form that can
    /// cross from the provider's callback.
    private enum Loaded: Sendable {
        case file(URL)
        case data(Data, suggestedName: String)
        case nothing
    }

    private func handOff() async {
        guard let container = AppGroup.containerURL else {
            return fail("Nimbus couldn't reach its shared folder.")
        }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let id = UUID()
        let directory = ShareInbox.folder(id: id, in: container)
        var items: [ShareInbox.Item] = []
        var taken: Set<String> = []
        var stagedBytes: Int64 = 0

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for provider in providers {
                switch await Self.load(provider) {
                case .file(let url) where !ShareInbox.needsStaging(path: url.path):
                    items.append(.init(path: url.path, staged: false))
                case .file(let url):
                    let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                    stagedBytes += size
                    guard stagedBytes <= ShareInbox.stagedByteLimit else { throw ShareInbox.Problem.tooLarge }
                    let name = ShareInbox.uniqueName(url.lastPathComponent, taken: taken)
                    taken.insert(name)
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(name))
                    items.append(.init(path: name, staged: true))
                case .data(let data, let suggestedName):
                    stagedBytes += Int64(data.count)
                    guard stagedBytes <= ShareInbox.stagedByteLimit else { throw ShareInbox.Problem.tooLarge }
                    let name = ShareInbox.uniqueName(suggestedName, taken: taken)
                    taken.insert(name)
                    try data.write(to: directory.appendingPathComponent(name))
                    items.append(.init(path: name, staged: true))
                case .nothing:
                    continue
                }
            }
            guard !items.isEmpty else {
                ShareInbox.remove(id: id, in: container)
                return fail("There was nothing here Nimbus can send.")
            }
            try ShareInbox.write(ShareInbox.Manifest(items: items), id: id, in: container)
        } catch ShareInbox.Problem.tooLarge {
            ShareInbox.remove(id: id, in: container)
            return fail("That's more than 2 GB to copy. Use Services > Send to Nimbus… in Finder instead.")
        } catch {
            ShareInbox.remove(id: id, in: container)
            return fail("Nimbus couldn't prepare these items: \(error.localizedDescription)")
        }

        NSWorkspace.shared.open(ShareInbox.handoffURL(id: id))
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func fail(_ message: String) {
        label.stringValue = message
        // Leave the sentence up long enough to read, then close the sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }

    /// A file where it is, when the provider has one; otherwise the bytes of
    /// an image or the text, to be written into the inbox.
    private static func load(_ provider: NSItemProvider) async -> Loaded {
        let suggested = provider.suggestedName
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let loaded: Loaded = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let url = item as? URL, url.isFileURL {
                        continuation.resume(returning: .file(url))
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil),
                              url.isFileURL {
                        continuation.resume(returning: .file(url))
                    } else {
                        continuation.resume(returning: .nothing)
                    }
                }
            }
            if case .file = loaded { return loaded }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let type = provider.registeredTypeIdentifiers.compactMap(UTType.init).first { $0.conforms(to: .image) }
            let ext = type?.preferredFilenameExtension ?? "png"
            return await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: (type ?? .image).identifier) { data, _ in
                    continuation.resume(returning: data.map {
                        .data($0, suggestedName: "\(suggested ?? "Image").\(ext)")
                    } ?? .nothing)
                }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    continuation.resume(returning: text.map {
                        .data(Data($0.utf8), suggestedName: "\(suggested ?? "Text").txt")
                    } ?? .nothing)
                }
            }
        }
        return .nothing
    }
}
