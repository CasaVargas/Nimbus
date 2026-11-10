import SwiftUI

struct EmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let messageVerbatim: String?
    let action: ActionConfig?

    struct ActionConfig {
        let label: LocalizedStringKey
        let perform: () -> Void
    }

    // Keep the existing localized-message init for compile-time literals
    init(icon: String, title: LocalizedStringKey, message: LocalizedStringKey?, action: ActionConfig?) {
        self.icon = icon
        self.title = title
        self.message = message
        self.messageVerbatim = nil
        self.action = action
    }

    // New init for runtime-supplied error messages — avoids LocalizedStringKey
    // wrapping which would defeat localization extractors and treat `%`/`%@`
    // in rclone errors as format specifiers.
    init(icon: String, title: LocalizedStringKey, messageVerbatim: String?, action: ActionConfig?) {
        self.icon = icon
        self.title = title
        self.message = nil
        self.messageVerbatim = messageVerbatim
        self.action = action
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            ContentUnavailableView {
                Label(title, systemImage: icon)
                    .font(DesignSystem.Typography.headline)
            } description: {
                if let messageVerbatim {
                    Text(verbatim: messageVerbatim)
                        .font(DesignSystem.Typography.callout)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                } else if let message {
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
                .buttonStyle(.primaryPill(.small))
            }
        }
        .frame(maxWidth: 440)
        .padding(DesignSystem.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Empty folder") {
    EmptyState(icon: "folder", title: "Empty Folder",
               message: "Drop files here or use ⌘N to create a folder.",
               action: .init(label: "New Folder", perform: {}))
}
