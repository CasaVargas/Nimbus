import SwiftUI
import RcloneKit

/// "New Encrypted Folder" (#68): pick a folder, set a password, done. The
/// folder becomes its own place in the sidebar and, like any new cloud, in
/// Finder. Logic lives in `EncryptedFolderSetup`.
struct EncryptedFolderSheet: View {
    let client: RcloneClient
    let remoteNames: [String]
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(FileProviderBridge.self) private var fileProviderBridge

    @State private var setup: EncryptedFolderSetup
    @State private var encryption: ConfigEncryptionModel
    @State private var finderFailures: [RemoteIntegrationFailure] = []

    init(
        client: RcloneClient,
        remoteNames: [String],
        setup: EncryptedFolderSetup? = nil,
        encryption: ConfigEncryptionModel = ConfigEncryptionModel(),
        onDismiss: @escaping () -> Void
    ) {
        self.client = client
        self.remoteNames = remoteNames
        self.onDismiss = onDismiss
        _setup = State(initialValue: setup ?? EncryptedFolderSetup(client: client, existingNames: Set(remoteNames)))
        _encryption = State(initialValue: encryption)
    }

    var body: some View {
        SheetChrome(title: "New Encrypted Folder", subtitle: nil) {
            content
        } actions: {
            actions
        }
        .frame(width: 560, height: 620)
        .task(id: settings.rcloneBinaryPath) {
            await encryption.refresh(binaryPath: settings.rcloneBinaryPath)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !finderFailures.isEmpty {
            FinderIntegrationWarning(failures: finderFailures) {
                Task { await retryFinder() }
            }
        } else if case .failed(let message) = setup.phase {
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "Couldn't Create the Folder",
                messageVerbatim: message,
                action: .init(label: "Try Again", perform: { setup.editAgain() })
            )
        } else {
            form
        }
    }

    private var form: some View {
        @Bindable var setup = setup
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            Text("Files are encrypted on this Mac before they're uploaded. The cloud only sees scrambled names and contents.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            FormSection(title: "Folder", footer: nil) {
                LocationPicker(label: "Encrypt", remoteNames: remoteNames, client: client, endpoint: $setup.folder)
                Text("Choose an empty or new folder, or one you encrypted before with Nimbus or rclone.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FormSection(title: "Name", footer: nil) {
                TextField("Name", text: $setup.name, prompt: Text("Shown in the sidebar and Finder"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Name")
                problemText(setup.nameProblem)
            }

            FormSection(title: "Password", footer: nil) {
                SecureField("Password", text: $setup.password,
                            prompt: Text("At least \(EncryptedFolderSetup.minimumPasswordLength) characters"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Password")
                SecureField("Confirm Password", text: $setup.confirmation, prompt: Text("Type it again"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Confirm Password")
                problemText(setup.passwordProblem)
            }

            DestructiveCallout(message: "If you forget this password, nobody can recover these files. Not even Nimbus.")
            Toggle("I've saved this password somewhere safe", isOn: $setup.acknowledged)
                .toggleStyle(.checkbox)

            if encryption.state == .plain {
                Label {
                    Text("The password is saved in rclone.conf, scrambled but not encrypted. Turn on **Settings › Advanced › Lock with Keychain** to encrypt it.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "key")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
        }
        .disabled(setup.phase == .creating)
    }

    @ViewBuilder
    private func problemText(_ problem: String?) -> some View {
        if let problem {
            Text(verbatim: problem)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.statusError)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !finderFailures.isEmpty {
            Button("Close") { dismiss() }
                .buttonStyle(.glassCapsule)
                .keyboardShortcut(.cancelAction)
        } else {
            if setup.phase == .creating {
                ProgressView().controlSize(.small)
                Text("Creating…")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(setup.phase == .creating)
            Button("Create") { Task { await create() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primaryPill(.small))
                .disabled(!setup.canCreate)
        }
    }

    private func create() async {
        await setup.create()
        guard case .created(let name) = setup.phase else { return }
        onDismiss()
        let result = await NewRemoteIntegration(domainAdder: fileProviderBridge).integrate(
            names: [name],
            addToFinder: settings.addNewRemotesToFinder,
            disabledDomainNames: settings.disabledFileProviderDomains
        )
        settings.disabledFileProviderDomains = result.disabledDomainNames
        finderFailures = result.failures
        if finderFailures.isEmpty { dismiss() }
    }

    private func retryFinder() async {
        finderFailures = await NewRemoteIntegration(domainAdder: fileProviderBridge)
            .integrate(names: finderFailures.map(\.remoteName), addToFinder: true)
        if finderFailures.isEmpty { dismiss() }
    }
}
