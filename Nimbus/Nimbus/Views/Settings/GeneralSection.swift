import SwiftUI

struct GeneralSection: View {
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(title: "Application", footer: nil) {
                FormRow(label: "Launch at Login", help: nil) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            if let error = launchAtLogin.lastError {
                Text(verbatim: error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.statusError)
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
        .onAppear { launchAtLogin.refresh() }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { newValue in
                if newValue {
                    launchAtLogin.register()
                } else {
                    Task { await launchAtLogin.unregister() }
                }
            }
        )
    }
}

#Preview {
    GeneralSection()
        .environment(LaunchAtLoginService())
        .frame(width: 480, height: 320)
}
