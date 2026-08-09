import SwiftUI

enum CloudStatus: Equatable {
    case local
    case cloud
    case downloading(progress: Double)
    case evicted
    case error(reason: String)
}

struct StatusBadge: View {
    let state: CloudStatus

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
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabelString))
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
