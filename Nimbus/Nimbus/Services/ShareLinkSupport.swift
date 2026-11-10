import Foundation

/// What a service's share links can do beyond "make one": which expiry
/// choices it honours and whether a link can be taken back.
///
/// rclone's `operations/fsinfo` only says whether a backend makes links, so
/// these lists come from reading each backend's `PublicLink` in rclone
/// 1.76.0. They are allow-lists on purpose: a backend that ignores `unlink`
/// answers a Stop Sharing request by making a new link.
struct ShareLinkSupport: Equatable, Sendable {
    enum Expiry: String, CaseIterable, Identifiable, Sendable {
        case never
        case day = "1d"
        case week = "7d"
        case month = "30d"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .never: "Never"
            case .day: "1 day"
            case .week: "7 days"
            case .month: "30 days"
            }
        }

        /// The rclone duration to send; nil asks for a link with no expiry.
        var duration: String? { self == .never ? nil : rawValue }
    }

    /// Empty when the service ignores `expire`: no menu is shown.
    let expiryChoices: [Expiry]
    let defaultExpiry: Expiry
    let canStopSharing: Bool

    /// - Parameter type: the rclone backend type, with aliases already
    ///   resolved (`CloudNaming.resolvedType`).
    static func forBackend(_ type: String) -> ShareLinkSupport {
        let canStop = unlinkBackends.contains(type)
        if type == "s3" {
            // Pre-signed: always expires, one week at most.
            return ShareLinkSupport(expiryChoices: [.day, .week], defaultExpiry: .week, canStopSharing: canStop)
        }
        if expiryBackends.contains(type) {
            return ShareLinkSupport(expiryChoices: Expiry.allCases, defaultExpiry: .never, canStopSharing: canStop)
        }
        return ShareLinkSupport(expiryChoices: [], defaultExpiry: .never, canStopSharing: canStop)
    }

    /// Dropbox is left out: it honours `expire` on paid plans only and
    /// rclone quietly drops it otherwise, so the caption would promise an
    /// expiry the link doesn't have.
    private static let expiryBackends: Set<String> = [
        "dosya", "filescom", "gofile", "kdrive", "onedrive", "pikpak", "storj",
    ]

    private static let unlinkBackends: Set<String> = [
        "gofile", "jottacloud", "kdrive", "pixeldrain", "yandex",
    ]

    static func copiedCaption(expiry: Expiry?) -> String {
        guard let expiry, expiry != .never else { return "Link copied." }
        return "Link copied. It stops working after \(expiry.title)."
    }
}
