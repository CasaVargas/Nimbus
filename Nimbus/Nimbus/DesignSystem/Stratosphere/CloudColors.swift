import SwiftUI

extension DesignSystem.Stratosphere {
    /// The two-stop colour a cloud owns: its ring segment, usage bar, card
    /// glow and page header all use it.
    public struct CloudColor: Hashable, Sendable {
        public let start: RGBA
        public let end: RGBA

        public init(_ start: UInt32, _ end: UInt32) {
            self.start = RGBA(hex: start)
            self.end = RGBA(hex: end)
        }

        public var gradient: LinearGradient {
            LinearGradient(colors: [start.color, end.color], startPoint: .leading, endPoint: .trailing)
        }
    }

    public enum CloudColors {
        /// Colours for backends people recognise, keyed by
        /// `ProviderCatalog.canonicalKey`. Chosen to sit apart on the
        /// backdrop, not to match each brand exactly: three of the most
        /// common services are all "brand blue".
        static let byProvider: [String: CloudColor] = [
            "drive": CloudColor(0x4C9BFF, 0x2563FF),
            "onedrive": CloudColor(0x2FD6F0, 0x0EA5E9),
            "dropbox": CloudColor(0x9B8CFF, 0x6D4DFF),
            "b2": CloudColor(0xFFB340, 0xFF6A3D),
            "box": CloudColor(0x5EEAD4, 0x14B8A6),
            "iclouddrive": CloudColor(0x7DD3FC, 0x38BDF8),
            "protondrive": CloudColor(0xF472B6, 0xDB2777),
            "mega": CloudColor(0xFF8A8A, 0xEF4444),
            "s3": CloudColor(0xFACC15, 0xEAB308),
            "gcs": CloudColor(0x86EFAC, 0x22C55E),
        ]

        /// Used for backends without an entry above, and for the second and
        /// later remotes on one backend.
        static let sequence: [CloudColor] = [
            CloudColor(0xC4B5FD, 0x8B5CF6),
            CloudColor(0x6EE7B7, 0x10B981),
            CloudColor(0xFDA4AF, 0xF43F5E),
            CloudColor(0xFCD34D, 0xF59E0B),
            CloudColor(0x67E8F9, 0x06B6D4),
            CloudColor(0xF0ABFC, 0xD946EF),
            CloudColor(0xA3ACC2, 0x6B7388),
        ]

        /// The colour of the first (or only) remote on a backend.
        public static func color(forProvider provider: String) -> CloudColor {
            let key = ProviderCatalog.canonicalKey(provider)
            if let known = byProvider[key] { return known }
            return sequence[Int(stableHash(key) % UInt64(sequence.count))]
        }

        /// A colour per remote name. Remotes on the same backend get
        /// different colours, so two Google accounts can be told apart. The
        /// result depends only on the set of remotes, never on their order.
        public static func assign(_ remotes: [(name: String, provider: String)]) -> [String: CloudColor] {
            var result: [String: CloudColor] = [:]
            let groups = Dictionary(grouping: remotes) { ProviderCatalog.canonicalKey($0.provider) }
            for (_, group) in groups {
                let names = group.map(\.name).sorted()
                guard let provider = group.first?.provider else { continue }
                let first = color(forProvider: provider)
                let others = sequence.filter { $0 != first }
                for (index, name) in names.enumerated() {
                    result[name] = index == 0 ? first : others[(index - 1) % others.count]
                }
            }
            return result
        }

        /// FNV-1a. `Hasher` is seeded per launch, which would reshuffle
        /// colours every time the app starts.
        private static func stableHash(_ string: String) -> UInt64 {
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            return hash
        }
    }
}
