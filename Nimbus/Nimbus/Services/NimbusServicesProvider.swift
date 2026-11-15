import AppKit

/// The app's entry in other apps' Services menus: "Send to Nimbus…" for
/// selected files and folders (declared under `NSServices` in
/// Config/Nimbus-Info.plist; `sendToNimbus` is the `NSMessage`).
@MainActor
final class NimbusServicesProvider: NSObject {
    /// Set by `NimbusApp` once the router exists. macOS can launch Nimbus
    /// for a service call and deliver it before that, so a request that
    /// arrives early waits here.
    var onSend: ((SendRequest) -> Void)? {
        didSet {
            if let onSend, let waiting {
                self.waiting = nil
                onSend(waiting)
            }
        }
    }

    private var waiting: SendRequest?

    @objc func sendToNimbus(
        _ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let request = Self.request(from: pasteboard) else {
            error.pointee = "There were no files to send."
            return
        }
        if let onSend { onSend(request) } else { waiting = request }
    }

    static func request(from pasteboard: NSPasteboard) -> SendRequest? {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return SendRequest(urls: urls)
    }
}
