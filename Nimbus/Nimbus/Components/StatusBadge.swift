import SwiftUI

enum CloudStatus: Equatable {
    case local
    case cloud
    case downloading(progress: Double)
    case evicted
    case error(reason: String)
}

struct StatusBadge: View {
    /// `.pill` is the labelled chip used in inspectors and transfer rows.
    /// `.compact` mirrors Finder's iCloud status column: nothing for local
    /// items, a bare glyph otherwise, so a folder full of synced files reads
    /// as calm instead of as a wall of green.
    enum Style {
        case pill
        case compact
    }

    let state: CloudStatus
    var style: Style = .pill

    var accessibilityLabelString: String {
        switch state {
        case .local:                      return "Local"
        case .cloud:                      return "Cloud only"
        case .downloading(let p):         return "Downloading \(Int((p * 100).rounded())) percent"
        case .evicted:                    return "Evicted from local cache"
        case .error(let reason):          return "Error: \(reason)"
        }
    }

    var body: some View {
        Group {
            switch style {
            case .pill: pillBody
            case .compact: compactBody
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabelString))
    }

    @ViewBuilder
    private var pillBody: some View {
        Group {
            switch state {
            case .local:              pill(text: "Local",   systemImage: "checkmark.circle.fill",
                                           tint: DesignSystem.Color.semantic.statusOK,       muted: false)
            case .cloud:              pill(text: "Cloud",   systemImage: "cloud",
                                           tint: DesignSystem.Color.semantic.textSecondary,  muted: true)
            case .downloading(let p): ring(progress: p)
            case .evicted:            pill(text: "Evicted", systemImage: "icloud.slash",
                                           tint: DesignSystem.Color.semantic.textTertiary,   muted: true)
            case .error:              pill(text: "Error",   systemImage: "exclamationmark.triangle.fill",
                                           tint: DesignSystem.Color.semantic.statusError,    muted: false)
            }
        }
    }

    @ViewBuilder
    private var compactBody: some View {
        switch state {
        case .local:
            Color.clear.frame(width: 16, height: 16)
        case .cloud:
            glyph("cloud", tint: DesignSystem.Color.semantic.textTertiary)
        case .downloading(let p):
            ring(progress: p)
        case .evicted:
            glyph("icloud.slash", tint: DesignSystem.Color.semantic.textTertiary)
        case .error:
            glyph("exclamationmark.triangle.fill", tint: DesignSystem.Color.semantic.statusError)
        }
    }

    private func glyph(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .foregroundStyle(tint)
            .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private func pill(text: String, systemImage: String, tint: Color, muted: Bool) -> some View {
        Label(text, systemImage: systemImage)
            .font(DesignSystem.Typography.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(muted ? 0.10 : 0.18),
                         in: RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous))
            .foregroundStyle(muted ? DesignSystem.Color.semantic.textSecondary : tint)
    }

    private func ring(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(DesignSystem.Color.semantic.accent.opacity(0.22), lineWidth: 1.4)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(DesignSystem.Color.semantic.accent,
                         style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Inner down-arrow. Use Image+resizable, not the forbidden font-size helper.
            Image(systemName: "arrow.down")
                .resizable()
                .scaledToFit()
                .frame(width: 8, height: 8)
                .foregroundStyle(DesignSystem.Color.semantic.accent)
        }
        .frame(width: 16, height: 16)
    }
}

#Preview("All states") {
    VStack(alignment: .leading, spacing: 4) {
        StatusBadge(state: .local)
        StatusBadge(state: .cloud)
        StatusBadge(state: .downloading(progress: 0.0))
        StatusBadge(state: .downloading(progress: 0.5))
        StatusBadge(state: .downloading(progress: 1.0))
        StatusBadge(state: .evicted)
        StatusBadge(state: .error(reason: "Auth failed"))
    }
    .padding()
}

#Preview("Compact") {
    HStack(spacing: 12) {
        StatusBadge(state: .local, style: .compact)
        StatusBadge(state: .cloud, style: .compact)
        StatusBadge(state: .downloading(progress: 0.5), style: .compact)
        StatusBadge(state: .evicted, style: .compact)
        StatusBadge(state: .error(reason: "Auth failed"), style: .compact)
    }
    .padding()
}
