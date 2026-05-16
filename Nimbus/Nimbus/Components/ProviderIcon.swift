import SwiftUI

/// Icon for an rclone backend. Shows a recognizable brand glyph (bundled
/// Simple Icons, tinted the brand's official color) when one exists, otherwise
/// a category-appropriate SF Symbol with a deterministic distinct color so no
/// two backends look identical.
struct ProviderIcon: View {
    let provider: String
    var size: CGFloat = 32

    var body: some View {
        let key = ProviderCatalog.canonicalKey(provider)
        if let brand = ProviderCatalog.brand[key] {
            Image(brand.asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(brand.displayColor)
        } else {
            let glyph = ProviderCatalog.symbol(for: key)
            Image(systemName: glyph.symbol)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(glyph.color)
        }
    }
}

/// App-icon-style provider badge: a rounded square filled with the provider's
/// brand color (subtle top-down gradient) with the glyph knocked out in white.
/// Uniform across bundled brand logos and SF Symbol fallbacks so the picker
/// grid reads as a cohesive set of "app icons".
struct ProviderBadge: View {
    let provider: String
    var size: CGFloat = 56

    var body: some View {
        let key = ProviderCatalog.canonicalKey(provider)
        let tint = ProviderCatalog.badgeTint(for: key)
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                glyph(key: key)
                    .frame(width: size * 0.52, height: size * 0.52)
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: tint.opacity(0.35), radius: size * 0.10, y: size * 0.05)
    }

    @ViewBuilder
    private func glyph(key: String) -> some View {
        if let brand = ProviderCatalog.brand[key] {
            Image(brand.asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: ProviderCatalog.symbol(for: key).symbol)
                .resizable()
                .scaledToFit()
        }
    }
}

enum ProviderCatalog {
    /// Maps the various raw spellings that reach the icon views — rclone
    /// `Provider.prefix` from the picker and the stored `remote.type` from
    /// RemoteRow — onto a single catalog key. Most backends already agree
    /// (e.g. "s3", "dropbox"); only the multi-word ones diverge.
    static func canonicalKey(_ raw: String) -> String {
        let k = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch k {
        case "google cloud storage": return "gcs"
        case "google photos": return "gphotos"
        case "oracleobjectstorage": return "oos"
        default: return k
        }
    }

    /// The provider's signature color — brand color when a logo exists,
    /// otherwise the deterministic SF Symbol fallback color.
    static func tint(for key: String) -> Color {
        if let brand = brand[key] { return brand.displayColor }
        return symbol(for: key).color
    }

    /// Fill color for `ProviderBadge`. Uses the raw brand color (the glyph is
    /// white, so dark brands stay dark for contrast) but floors near-black at
    /// a dark slate so a logo like Filen reads as a tile, not a void.
    static func badgeTint(for key: String) -> Color {
        guard let brand = brand[key] else { return symbol(for: key).color }
        let r = Double((brand.hex >> 16) & 0xFF) / 255
        let g = Double((brand.hex >> 8) & 0xFF) / 255
        let b = Double(brand.hex & 0xFF) / 255
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luma < 0.10 { return Color(red: 0.17, green: 0.17, blue: 0.18) }
        return Color(red: r, green: g, blue: b)
    }

    struct Brand {
        let asset: String
        let hex: UInt

        /// Brand color, lightened toward a visible neutral when the official
        /// color is near-black (e.g. Filen) so it survives a dark surface.
        var displayColor: Color {
            let r = Double((hex >> 16) & 0xFF) / 255
            let g = Double((hex >> 8) & 0xFF) / 255
            let b = Double(hex & 0xFF) / 255
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if luma < 0.15 { return Color(nsColor: .labelColor) }
            return Color(red: r, green: g, blue: b)
        }
    }

    /// rclone backend name → bundled Simple Icons asset + official brand hex.
    static let brand: [String: Brand] = [
        "azureblob": .init(asset: "microsoftazure", hex: 0x0078D4),
        "azurefiles": .init(asset: "microsoftazure", hex: 0x0078D4),
        "b2": .init(asset: "backblaze", hex: 0xE21E29),
        "box": .init(asset: "box", hex: 0x0061D5),
        "cloudinary": .init(asset: "cloudinary", hex: 0x3448C5),
        "drive": .init(asset: "googledrive", hex: 0x4285F4),
        "dropbox": .init(asset: "dropbox", hex: 0x0061FF),
        "filen": .init(asset: "filen", hex: 0x000000),
        "gcs": .init(asset: "googlecloud", hex: 0x4285F4),
        "gphotos": .init(asset: "googlephotos", hex: 0x4285F4),
        "huaweidrive": .init(asset: "huawei", hex: 0xFF0000),
        "iclouddrive": .init(asset: "icloud", hex: 0x3693F3),
        "internetarchive": .init(asset: "internetarchive", hex: 0x666666),
        "mailru": .init(asset: "maildotru", hex: 0x005FF9),
        "mega": .init(asset: "mega", hex: 0xD9272E),
        "netstorage": .init(asset: "akamai", hex: 0x0096D6),
        "onedrive": .init(asset: "microsoftonedrive", hex: 0x0078D4),
        "oos": .init(asset: "oracle", hex: 0xF80000),
        "protondrive": .init(asset: "protondrive", hex: 0xEB508D),
        "s3": .init(asset: "amazons3", hex: 0x569A31),
        "seafile": .init(asset: "seafile", hex: 0xFF9800),
        "sharefile": .init(asset: "citrix", hex: 0x452170),
        "swift": .init(asset: "openstack", hex: 0xED1944),
        "yandex": .init(asset: "yandexcloud", hex: 0x5282FF),
        "zoho": .init(asset: "zoho", hex: 0xE42527),
    ]

    /// SF Symbol + color for backends without a bundled brand glyph. Known
    /// backends get a meaningful symbol; anything else gets `cloud.fill` with a
    /// color deterministically picked from a palette so the grid stays varied.
    static func symbol(for name: String) -> (symbol: String, color: Color) {
        let palette: [Color] = [
            Color(nsColor: .systemBlue), Color(nsColor: .systemPurple),
            Color(nsColor: .systemTeal), Color(nsColor: .systemIndigo),
            Color(nsColor: .systemPink), Color(nsColor: .systemMint),
            Color(nsColor: .systemCyan), Color(nsColor: .systemBrown),
        ]
        func paletteColor(_ s: String) -> Color {
            var h: UInt64 = 1469598103934665603
            for byte in s.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
            return palette[Int(h % UInt64(palette.count))]
        }

        switch name {
        case "sharepoint":
            return ("cloud.fill", Color(red: 0.0, green: 0.47, blue: 0.83))
        case "storj", "tardigrade":
            return ("cube.transparent.fill", Color(red: 0.15, green: 0.51, blue: 1.0))
        case "pcloud":
            return ("externaldrive.fill.badge.icloud", Color(nsColor: .systemPurple))
        case "jottacloud", "hidrive", "koofr", "quatrix", "filefabric", "drime":
            return ("cloud.fill", paletteColor(name))
        case "sftp", "ftp":
            return ("server.rack", Color(nsColor: .systemGray))
        case "http":
            return ("globe", Color(nsColor: .systemTeal))
        case "webdav":
            return ("globe.americas.fill", Color(nsColor: .systemBlue))
        case "smb":
            return ("externaldrive.connected.to.line.below.fill", Color(nsColor: .systemBlue))
        case "hdfs":
            return ("cylinder.split.1x2.fill", Color(nsColor: .systemBrown))
        case "local":
            return ("internaldrive.fill", Color(nsColor: .systemGray))
        case "alias":
            return ("arrowshape.turn.up.right.fill", Color(nsColor: .systemGray))
        case "crypt":
            return ("lock.shield.fill", Color(nsColor: .systemGreen))
        case "union", "combine":
            return ("rectangle.3.group.fill", Color(nsColor: .systemIndigo))
        case "chunker":
            return ("square.split.2x1.fill", Color(nsColor: .systemBrown))
        case "compress":
            return ("arrow.down.right.and.arrow.up.left", Color(nsColor: .systemTeal))
        case "cache":
            return ("bolt.horizontal.fill", Color(nsColor: .systemYellow))
        case "hasher":
            return ("number.square.fill", Color(nsColor: .systemGray))
        case "memory":
            return ("memorychip.fill", Color(nsColor: .systemGray))
        case "archive":
            return ("archivebox.fill", Color(nsColor: .systemBrown))
        case "doi":
            return ("doc.text.fill", Color(nsColor: .systemGray))
        case "pixeldrain", "filelu", "fichier", "gofile":
            return ("drop.fill", paletteColor(name))
        default:
            return ("cloud.fill", paletteColor(name))
        }
    }
}

#Preview {
    let names = ["drive", "dropbox", "s3", "onedrive", "b2", "box", "mega",
                 "protondrive", "iclouddrive", "swift", "yandex", "zoho",
                 "crypt", "ftp", "webdav", "local", "hdfs", "pcloud",
                 "storj", "koofr", "fichier", "doi"]
    return ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104))], spacing: 12) {
            ForEach(names, id: \.self) { n in
                VStack(spacing: 8) {
                    ProviderBadge(provider: n, size: 52)
                    Text(n).font(.caption)
                }
                .frame(width: 104, height: 104)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
    }
    .frame(width: 480, height: 560)
}
