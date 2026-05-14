import SwiftUI

struct EmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let action: ActionConfig?

    struct ActionConfig {
        let label: LocalizedStringKey
        let perform: () -> Void
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            ContentUnavailableView {
                Label(title, systemImage: icon)
                    .font(DesignSystem.Typography.headline)
            } description: {
                if let message {
                    Text(message)
                        .font(DesignSystem.Typography.callout)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                }
            }
            if let action {
                Button {
                    action.perform()
                } label: {
                    Text(action.label)
                        .font(DesignSystem.Typography.body)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Empty folder") {
    EmptyState(icon: "folder", title: "Empty Folder",
               message: "Drop files here or use ⌘N to create a folder.",
               action: .init(label: "New Folder", perform: {}))
}
