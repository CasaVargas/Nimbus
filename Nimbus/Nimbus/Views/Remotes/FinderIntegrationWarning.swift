import SwiftUI

struct FinderIntegrationWarning: View {
    let failures: [RemoteIntegrationFailure]
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            Label("Finder Integration Needs Attention", systemImage: "exclamationmark.triangle.fill")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.statusWarning)

            ForEach(failures) { failure in
                Text(verbatim: "\(failure.remoteName): \(failure.message)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Retry Finder Integration", action: retry)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.statusWarning.opacity(0.10))
        )
    }
}
