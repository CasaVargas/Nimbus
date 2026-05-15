import SwiftUI

struct AppearanceSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(title: "Appearance", footer: nil) {
                FormRow(label: "Color Scheme", help: nil) {
                    Picker("", selection: $settings.appearance) {
                        Text("System").tag(Appearance.system)
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
    }
}

#Preview {
    AppearanceSection()
        .environment(AppSettings())
        .frame(width: 480, height: 320)
}
