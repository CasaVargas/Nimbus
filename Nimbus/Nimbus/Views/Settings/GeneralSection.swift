import SwiftUI

struct GeneralSection: View {
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    var body: some View {
        Form {
            Toggle("Launch Nimbus at login", isOn: launchAtLoginBinding)
            if let error = launchAtLogin.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
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

#Preview("Idle") {
    GeneralSection()
        .environment(LaunchAtLoginService())
        .frame(width: 450, height: 250)
        .padding()
}
