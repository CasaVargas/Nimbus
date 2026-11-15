import RcloneKit
import SwiftUI

/// Saving the pair on a remote, abstracted so the sheet can be tested
/// without a daemon.
protocol ClientIDSaving: Sendable {
    func setRemoteParameters(name: String, parameters: [String: String]) async throws
}

extension RcloneClient: ClientIDSaving {}

/// Walks the user through giving a Google Drive cloud its own Google client
/// ID, in place of rclone's shared one. Saving hands straight on to signing
/// in again: the old token belongs to the shared ID.
struct OwnClientIDSheet: View {
    let cloudName: String
    let client: any ClientIDSaving
    /// Called after the pair is saved; the caller starts the sign-in.
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var problem: String?
    @State private var isSaving = false

    static let consoleURL = URL(string: "https://console.cloud.google.com/apis/credentials")!
    static let guideURL = URL(string: "https://rclone.org/drive/#making-your-own-client-id")!

    static let steps = [
        "In Google Cloud Console, create a project (any name).",
        "Enable the Google Drive API for it.",
        "Set up the OAuth consent screen as External, then publish it. Left in Testing, Google signs you out every week.",
        "Create credentials: OAuth client ID, application type Desktop app.",
        "Paste the client ID and client secret below.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Use your own Google sign-in for \(cloudName)")
                    .font(DesignSystem.Typography.titleEmphasized)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Right now it signs in through an ID shared by everyone who uses rclone, the engine Nimbus runs on. Google limits that ID, so folders can be slow to open or time out, and it stops working during 2026. Your own is free and only you use it.")
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.s) {
                        Text("\(index + 1).")
                            .font(DesignSystem.Typography.bodyEmphasized)
                            .monospacedDigit()
                        Text(step)
                            .font(DesignSystem.Typography.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: DesignSystem.Spacing.l) {
                    Link("Open Google Cloud Console", destination: Self.consoleURL)
                    Link("Step-by-step guide", destination: Self.guideURL)
                }
                .font(DesignSystem.Typography.callout)
                .padding(.top, DesignSystem.Spacing.xs)
            }
            .padding(DesignSystem.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .fill(DesignSystem.Color.semantic.surfaceSubtle)
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                TextField("Client ID", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Client ID")
                SecureField("Client secret", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Client secret")
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(DesignSystem.Typography.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: DesignSystem.Spacing.s) {
                Text("You'll sign in to Google again next.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glassCapsule)
                Button("Save and Sign In") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primaryPill(.small))
                    .disabled(isSaving)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 520)
    }

    private func save() {
        switch SharedGoogleClientID.validate(id: clientID, secret: clientSecret) {
        case .failure(let issue):
            problem = issue.message
        case .success(let pair):
            problem = nil
            isSaving = true
            Task {
                defer { isSaving = false }
                do {
                    try await Self.save(pair.id, pair.secret, on: cloudName, with: client)
                    dismiss()
                    onSaved()
                } catch {
                    problem = NimbusError.classify(error).message
                }
            }
        }
    }

    /// The one write this sheet makes: the pair, and nothing else.
    static func save(_ id: String, _ secret: String, on cloud: String, with client: any ClientIDSaving) async throws {
        try await client.setRemoteParameters(
            name: cloud, parameters: ["client_id": id, "client_secret": secret]
        )
    }
}
