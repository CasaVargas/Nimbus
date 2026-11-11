import Foundation

/// What check rclone could run on a finished transfer (#75). rclone compares
/// size, then the first hash type both sides share, after every file it
/// writes, and fails the transfer on a mismatch. So the shared hash types,
/// from `operations/fsinfo`, tell us which check a successful job got.
/// See docs/superpowers/specs/2026-11-11-verified-transfers-design.md.
enum TransferVerification: Codable, Equatable, Sendable {
    /// Succeeded between locations sharing `hash` (an rclone hash name).
    case verified(hash: String)
    /// Succeeded, but the two sides share no hash type: sizes only.
    case sizeOnly
    /// Failed because a copied file's checksum didn't match.
    case mismatch

    /// The state for a successful job, from each side's `Hashes`. Uses the
    /// first source type the destination also has, the one rclone picks.
    static func infer(sourceHashes: [String], destinationHashes: [String]) -> TransferVerification {
        let destination = Set(destinationHashes.map { $0.lowercased() })
        if let shared = sourceHashes.first(where: { destination.contains($0.lowercased()) }) {
            return .verified(hash: shared.lowercased())
        }
        return .sizeOnly
    }

    /// True when a failure message is rclone's hash check failing
    /// (`corrupted on transfer: md5 hashes differ src(…) … vs dst(…) …`).
    /// A size mismatch ("sizes differ") is not a checksum mismatch.
    static func isMismatch(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        return message.contains("hashes differ") || message.contains("hash differ")
    }

    /// The remote part of an fs string that `operations/fsinfo` answers for:
    /// `"Drive:Photos/a.jpg"` → `"Drive:"`. Local paths share one key, `"/"`.
    /// An on-the-fly remote (`":s3,provider=AWS:bucket"`) is kept whole.
    static func remoteRoot(of fs: String) -> String {
        if fs.hasPrefix(":") { return fs }
        guard !fs.hasPrefix("/"), let colon = fs.firstIndex(of: ":") else { return "/" }
        return String(fs[...colon])
    }

    /// How a hash is named in the UI.
    static func displayName(ofHash hash: String) -> String {
        switch hash.lowercased() {
        case "md5": "MD5"
        case "sha1": "SHA-1"
        case "sha256": "SHA-256"
        case "sha512": "SHA-512"
        case "crc32": "CRC32"
        case "crc32c": "CRC32C"
        case "quickxor": "QuickXorHash"
        case "dropbox": "Dropbox content hash"
        case "whirlpool": "Whirlpool"
        case "blake3": "BLAKE3"
        case "xxh3": "XXH3"
        case "xxh128": "XXH128"
        default: hash.uppercased()
        }
    }
}
