import SwiftUI
import RcloneKit

/// One side of a two-place screen (Copy Between Clouds, Compare): a glass
/// well washed in its cloud's colour, saying what's chosen, with a
/// `LocationPicker` beneath.
struct EndpointWell: View {
    let title: LocalizedStringKey
    let label: LocalizedStringKey
    let remoteNames: [String]
    let client: RcloneClient
    @Binding var endpoint: TransferEndpoint?

    @Environment(\.stratosphere) private var palette
    @Environment(\.cloudColors) private var cloudColors
    /// Optional so previews without a live window still render.
    @Environment(CloudMonitor.self) private var monitor: CloudMonitor?

    private typealias S = DesignSystem.Stratosphere

    var body: some View {
        let place = Place(endpoint: endpoint, remotes: monitor?.remotes ?? [])
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            Text(title)
                .font(S.Typography.segment)
                .foregroundStyle(palette.textSecondary.color)
            HStack(spacing: DesignSystem.Spacing.m) {
                if let provider = place.provider {
                    LogoTile(provider: provider)
                } else {
                    IconTile(systemImage: place.symbol, color: S.CloudColors.sequence[6], size: 42)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: place.title)
                        .font(S.Typography.sectionTitle)
                        .foregroundStyle(palette.textPrimary.color)
                        .lineLimit(1)
                    Text(verbatim: place.detail)
                        .font(S.Typography.detail)
                        .foregroundStyle(palette.textSecondary.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            LocationPicker(
                label: label,
                remoteNames: remoteNames,
                client: client,
                endpoint: $endpoint,
                layout: .stacked
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: S.Radius.header, tint: place.cloud.flatMap { cloudColors[$0] })
    }

    /// What a well says about its current choice.
    private struct Place {
        let title: String
        let detail: String
        let provider: String?
        let symbol: String
        let cloud: String?

        init(endpoint: TransferEndpoint?, remotes: [Remote]) {
            switch endpoint {
            case .cloud(let remote, let path):
                title = remote
                let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                detail = trimmed.isEmpty ? "The whole cloud" : trimmed
                provider = remotes.first { $0.name == remote }.map { CloudNaming.resolvedType(of: $0, in: remotes) }
                symbol = "cloud.fill"
                cloud = remote
            case .local(let path):
                title = "This Mac"
                detail = (path as NSString).abbreviatingWithTildeInPath
                provider = nil
                symbol = "desktopcomputer"
                cloud = nil
            case nil:
                title = "Choose a place"
                detail = "A cloud, or a folder on this Mac"
                provider = nil
                symbol = "questionmark"
                cloud = nil
            }
        }
    }
}

/// The round action-gradient badge between two wells.
struct WellConnector: View {
    let systemImage: String

    @Environment(\.stratosphere) private var palette

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [palette.actionTop.color, palette.actionBottom.color],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: systemImage)
                    .font(DesignSystem.Typography.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.onAction.color)
            }
            .shadow(color: palette.actionGlow.color, radius: 12, y: 6)
            .accessibilityHidden(true)
    }
}
