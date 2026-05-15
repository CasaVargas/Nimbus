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
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                if state == .complete, let secondaryAction {
                    Button {
                        secondaryAction.perform()
                    } label: {
                        Text(secondaryAction.label)
                            .font(DesignSystem.Typography.callout)
                            .foregroundStyle(DesignSystem.Color.semantic.accent)
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
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(DesignSystem.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.surfaceSubtle)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(accessibilityHint))
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .pending:
            Circle()
                .strokeBorder(DesignSystem.Color.semantic.textTertiary, lineWidth: 1.5)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(DesignSystem.Color.semantic.statusOK)
        case .actionRequired:
            Circle()
                .fill(DesignSystem.Color.semantic.accent)
        }
    }

    private var iconTint: Color {
        switch state {
        case .actionRequired: return DesignSystem.Color.semantic.statusInfo
        case .complete: return DesignSystem.Color.semantic.statusOK
        default: return DesignSystem.Color.semantic.textSecondary
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
            title: "Add a Remote",
            message: "Connect a cloud provider to get started.",
            primaryAction: .init(label: "Add Remote", perform: {}),
            secondaryAction: nil
        )
        OnboardingCard(
            state: .complete,
            icon: "cloud",
            title: "Add a Remote",
            message: "Connected to gdrive.",
            primaryAction: nil,
            secondaryAction: .init(label: "Mount it for Finder →", perform: {})
        )
        OnboardingCard(
            state: .pending,
            icon: "externaldrive",
            title: "Mount Your Remote",
            message: "Mount the remote to access it in Finder.",
            primaryAction: nil,
            secondaryAction: nil
        )
    }
    .padding(DesignSystem.Spacing.xl)
    .frame(width: 560)
}
