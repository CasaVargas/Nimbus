import SwiftUI

struct AboutSection: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            Spacer()
            Image(systemName: "cloud")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .foregroundStyle(DesignSystem.Color.semantic.statusInfo)

            Text(verbatim: "Nimbus")
                .font(DesignSystem.Typography.largeTitle.bold())
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)

            Text(verbatim: "Version \(appVersion) (\(buildNumber))")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)

            Spacer()

            Link(destination: URL(string: "https://rclone.org/")!) {
                Text("Powered by rclone")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xl)
    }
}

#Preview {
    AboutSection()
        .frame(width: 480, height: 320)
}
