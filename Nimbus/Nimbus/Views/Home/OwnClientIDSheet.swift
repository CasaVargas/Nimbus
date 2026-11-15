import RcloneKit
import SwiftUI
import UniformTypeIdentifiers

/// Saving the pair on a remote, abstracted so the sheet can be tested
/// without a daemon.
protocol ClientIDSaving: Sendable {
    func setRemoteParameters(name: String, parameters: [String: String]) async throws
}

extension RcloneClient: ClientIDSaving {}

/// Walks the user through giving Google Drive clouds their own Google
/// client ID, in place of rclone's shared one. Saving hands straight on to
/// signing in again: the old tokens belong to the shared ID.
struct OwnClientIDSheet: View {
    let cloudName: String
    /// Other Drive clouds still on the shared ID. One client ID serves
    /// them all, so they're offered in the same pass.
    var otherClouds: [String] = []
    let client: any ClientIDSaving
    /// Called with every cloud the pair was saved on; the caller signs
    /// each in again.
    let onSaved: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var problem: String?
    @State private var isSaving = false
    @State private var isChoosingFile = false
    @State private var isDropTargeted = false
    @State private var skipped: Set<String> = []
    /// Clouds already saved by a pass that then failed on a later one.
    @State private var saved: [String] = []

    struct Step: Equatable {
        let text: String
        let linkTitle: String?
        let url: URL?

        init(_ text: String, _ linkTitle: String? = nil, _ url: String? = nil) {
            self.text = text
            self.linkTitle = linkTitle
            self.url = url.flatMap(URL.init(string:))
        }
    }

    static let steps = [
        Step("Create a project in Google Cloud Console. Any name will do.",
             "Create project", "https://console.cloud.google.com/projectcreate"),
        Step("Enable the Google Drive API for it.",
             "Open Drive API", "https://console.cloud.google.com/apis/library/drive.googleapis.com"),
        Step("Set up the OAuth consent screen as External, then publish it. Left in Testing, Google signs you out every week.",
             "Open consent screen", "https://console.cloud.google.com/apis/credentials/consent"),
        Step("Create credentials: OAuth client ID, application type Desktop app. Then click Download JSON.",
             "Open credentials", "https://console.cloud.google.com/apis/credentials"),
        Step("Drop the downloaded file here, or paste the client ID and secret below."),
    ]
    static let guideURL = URL(string: "https://rclone.org/drive/#making-your-own-client-id")!
    static let accessBlockedHint = "If Google says “Access blocked” when you sign in, the consent screen is still in Testing: publish it, or add your Google account under Test users."

    private var targets: [String] {
        [cloudName] + otherClouds.filter { !skipped.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            header
            stepList
            fields
            if !otherClouds.isEmpty { others }
            footer
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 560)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sheet, style: .continuous)
                    .strokeBorder(DesignSystem.Color.semantic.selection, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { load(url) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Use your own Google sign-in for \(cloudName)")
                .font(DesignSystem.Typography.titleEmphasized)
                .fixedSize(horizontal: false, vertical: true)
            Text("Right now it signs in through an ID shared by everyone who uses rclone, the engine Nimbus runs on. Google limits that ID, so folders can be slow to open or time out, and it stops working during 2026. Your own is free and only you use it.")
                .font(DesignSystem.Typography.callout)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.s) {
                    Text("\(index + 1).")
                        .font(DesignSystem.Typography.bodyEmphasized)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.text)
                            .font(DesignSystem.Typography.body)
                            .fixedSize(horizontal: false, vertical: true)
                        if let title = step.linkTitle, let url = step.url {
                            Link(title, destination: url)
                                .font(DesignSystem.Typography.callout)
                        }
                    }
                }
            }
            Text(Self.accessBlockedHint)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DesignSystem.Spacing.xs)
            Link("Step-by-step guide with pictures", destination: Self.guideURL)
                .font(DesignSystem.Typography.caption)
        }
        .padding(DesignSystem.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.surfaceSubtle)
        )
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            HStack(spacing: DesignSystem.Spacing.s) {
                TextField("Client ID", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Client ID")
                Button("Choose File…") { isChoosingFile = true }
                    .buttonStyle(.glassCapsule)
            }
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
    }

    private var others: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("One client ID works for all your Google Drive clouds. Also use it for:")
                .font(DesignSystem.Typography.callout)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            ForEach(otherClouds, id: \.self) { name in
                Toggle(isOn: Binding(
                    get: { !skipped.contains(name) },
                    set: { if $0 { skipped.remove(name) } else { skipped.insert(name) } }
                )) {
                    Text(verbatim: name)
                }
                .toggleStyle(.checkbox)
                .disabled(saved.contains(name))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Text(Self.signInNote(count: targets.count))
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Spacer()
            if isSaving { ProgressView().controlSize(.small) }
            Button("Cancel") { close() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glassCapsule)
            Button("Save and Sign In") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primaryPill(.small))
                .disabled(isSaving)
        }
    }

    static func signInNote(count: Int) -> String {
        count == 1 ? "You'll sign in to Google again next." : "You'll sign in to Google again next, once for each cloud."
    }

    /// Fills the fields from Google's downloaded file.
    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            problem = SharedGoogleClientID.FileProblem.unreadable.message
            return
        }
        switch SharedGoogleClientID.pair(fromDownloadedJSON: data) {
        case .success(let pair):
            clientID = pair.id
            clientSecret = pair.secret
            problem = nil
        case .failure(let issue):
            problem = issue.message
        }
    }

    private func save() {
        switch SharedGoogleClientID.validate(id: clientID, secret: clientSecret) {
        case .failure(let issue):
            problem = issue.message
        case .success(let pair):
            problem = nil
            isSaving = true
            let pending = targets.filter { !saved.contains($0) }
            Task {
                defer { isSaving = false }
                let outcome = await Self.save(pair.id, pair.secret, on: pending, with: client)
                saved += outcome.saved
                if let failure = outcome.failure {
                    problem = "Couldn't save it for \(failure.cloud): \(NimbusError.classify(failure.error).message)"
                } else {
                    close()
                }
            }
        }
    }

    /// Closing always reports what was saved, even after a partial failure
    /// or Cancel: those clouds need their sign-in either way.
    private func close() {
        dismiss()
        if !saved.isEmpty { onSaved(saved) }
    }

    /// The only writes this sheet makes: the pair, on each cloud in turn,
    /// stopping at the first that fails.
    static func save(
        _ id: String, _ secret: String, on clouds: [String], with client: any ClientIDSaving
    ) async -> (saved: [String], failure: (cloud: String, error: any Error)?) {
        var saved: [String] = []
        for cloud in clouds {
            do {
                try await client.setRemoteParameters(
                    name: cloud, parameters: ["client_id": id, "client_secret": secret]
                )
                saved.append(cloud)
            } catch {
                return (saved, (cloud, error))
            }
        }
        return (saved, nil)
    }
}
