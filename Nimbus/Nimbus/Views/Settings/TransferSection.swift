import SwiftUI

struct TransferSection: View {
    @Environment(AppSettings.self) private var settings
    @State private var bandwidthLimitDraft: String = ""
    @State private var bandwidthInvalid = false

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(
                title: "Transfers",
                footer: "Higher concurrency improves throughput but uses more memory."
            ) {
                FormRow(label: "Concurrent Transfers", help: nil) {
                    Stepper(value: $settings.concurrentTransfers, in: 1...32) {
                        Text(verbatim: "\(settings.concurrentTransfers)")
                    }
                    .frame(maxWidth: 160)
                }
                FormRow(label: "Bandwidth Limit", help: "e.g., 1M, 10M, 100k, or empty for unlimited.") {
                    TextField("Unlimited", text: $bandwidthLimitDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                        .onAppear { bandwidthLimitDraft = settings.bandwidthLimit }
                        .onChange(of: bandwidthLimitDraft) { _, newValue in
                            if isValidBandwidth(newValue) {
                                bandwidthInvalid = false
                                settings.bandwidthLimit = newValue
                            } else {
                                bandwidthInvalid = true
                            }
                        }
                }
            }
            if bandwidthInvalid {
                Text(verbatim: "Use a number with k/M/G suffix (e.g., 10M), or leave empty.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.statusError)
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
    }

    /// Accepts empty (unlimited), or a number with optional k/M/G/T suffix.
    /// Examples that pass: "", "10M", "100k", "2.5G", "500".
    /// Examples that fail: "10MB", "abc", "10.5.5".
    private func isValidBandwidth(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        let pattern = #"^\d+(\.\d+)?[kMGTkmgt]?$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

#Preview {
    TransferSection()
        .environment(AppSettings())
        .frame(width: 480, height: 320)
}
