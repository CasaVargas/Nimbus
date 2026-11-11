import SwiftUI

enum OnboardingCardState: Equatable, Sendable {
    case pending
    case inProgress
    case complete
    case actionRequired
}

/// Progressive state-machine card for the Onboarding flow.
/// Reference: macOS Setup Assistant (iCloud / Apple ID setup) step cards.
struct OnboardingCard: View {
    let state: OnboardingCardState
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let primaryAction: ActionConfig?
    let secondaryAction: ActionConfig?

    @Environment(\.stratosphere) private var palette

    struct ActionConfig {
        let label: LocalizedStringKey
        let perform: @MainActor () -> Void
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.m) {
            stateIndicator
                .frame(width: 24, height: 24)

            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(iconTint)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(DesignSystem.Stratosphere.Typography.sectionTitle)
                    .foregroundStyle(palette.textPrimary.color)
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(palette.textSecondary.color)
                if state == .complete || state == .actionRequired, let secondaryAction {
                    Button {
                        secondaryAction.perform()
                    } label: {
                        Text(secondaryAction.label)
                            .font(DesignSystem.Stratosphere.Typography.segment)
                            .foregroundStyle(palette.textPrimary.color)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            Spacer()

            if let primaryAction, state == .actionRequired || state == .complete {
                Button {
                    primaryAction.perform()
                } label: {
                    Text(primaryAction.label)
                }
                .buttonStyle(.primaryPill(.small))
            }
        }
        .padding(DesignSystem.Spacing.l)
        // Glass without the blur: this card is snapshot-tested, and a blur
        // material renders differently on every machine.
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Stratosphere.Radius.card, style: .continuous)
                .fill(LinearGradient(colors: [palette.glassTop.color, palette.glassBottom.color],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.Stratosphere.Radius.card, style: .continuous)
                        .strokeBorder(palette.glassBorder.color, lineWidth: 1)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(accessibilityHint))
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .pending:
            Circle()
                .strokeBorder(palette.textTertiary.color, lineWidth: 1.5)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(palette.ok.color)
        case .actionRequired:
            Circle()
                .fill(palette.actionTop.color)
        }
    }

    private var iconTint: Color {
        switch state {
        case .actionRequired: return palette.actionTop.color
        case .complete: return palette.ok.color
        default: return palette.textSecondary.color
        }
    }

    private var accessibilityHint: String {
        switch state {
        case .pending: return "Pending"
        case .inProgress: return "In progress"
        case .complete: return "Complete"
        case .actionRequired: return "Action required"
        }
    }
}

#Preview {
    VStack(spacing: DesignSystem.Spacing.m) {
        OnboardingCard(
            state: .complete,
            icon: "checkmark.seal.fill",
            title: "You're All Set",
            message: "Nimbus is ready to manage your cloud storage.",
            primaryAction: .init(label: "Done", perform: {}),
            secondaryAction: nil
        )
        OnboardingCard(
            state: .actionRequired,
            icon: "cloud",
            title: "Add a Cloud",
            message: "Connect a cloud service to get started.",
            primaryAction: .init(label: "Add Remote", perform: {}),
            secondaryAction: nil
        )
        OnboardingCard(
            state: .complete,
            icon: "cloud",
            title: "Add a Cloud",
            message: "Connected to Personal.",
            primaryAction: nil,
            secondaryAction: .init(label: "Mount it for Finder →", perform: {})
        )
        OnboardingCard(
            state: .pending,
            icon: "externaldrive",
            title: "Add It to Finder",
            message: "Show your cloud beside iCloud Drive in Finder.",
            primaryAction: nil,
            secondaryAction: nil
        )
    }
    .padding(DesignSystem.Spacing.xl)
    .frame(width: 560)
}
