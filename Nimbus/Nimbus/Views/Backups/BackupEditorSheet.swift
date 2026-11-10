import SwiftUI
import RcloneKit

/// Creates or edits a saved backup. Saving a change that alters what a run
/// does ("Save and Preview…") clears the approval and opens the preview.
struct BackupEditorSheet: View {
    let original: BackupJob?
    let remoteNames: [String]
    let client: RcloneClient
    /// The saved job, and whether it needs a (new) preview before it can run.
    let onSave: (BackupJob, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    @State private var name: String
    /// The last name Nimbus suggested; a name the user typed is never replaced.
    @State private var suggestedName: String?
    @State private var source: TransferEndpoint?
    @State private var destination: TransferEndpoint?
    @State private var mode: BackupJob.Mode
    @State private var versionsEnabled: Bool
    @State private var versionsInside: Bool
    @State private var versionsFolder: TransferEndpoint?
    @State private var versionsKeep: BackupJob.Versions.Keep
    @State private var excludes: [String]
    @State private var limitEnabled: Bool
    @State private var limit: Int
    @State private var schedule: BackupScheduleDraft

    init(
        original: BackupJob?,
        draft: BackupJob? = nil,
        remoteNames: [String],
        client: RcloneClient,
        onSave: @escaping (BackupJob, Bool) -> Void
    ) {
        self.original = original
        self.remoteNames = remoteNames
        self.client = client
        self.onSave = onSave
        let seed = original ?? draft
        _name = State(initialValue: seed?.name ?? "")
        _suggestedName = State(initialValue: original == nil ? seed?.name : nil)
        _source = State(initialValue: seed?.source)
        _destination = State(initialValue: seed?.destination)
        _mode = State(initialValue: seed?.mode ?? .mirror)
        _versionsEnabled = State(initialValue: seed?.versions.enabled ?? true)
        if case .custom(let folder) = seed?.versions.location {
            _versionsInside = State(initialValue: false)
            _versionsFolder = State(initialValue: folder)
        } else {
            _versionsInside = State(initialValue: true)
            _versionsFolder = State(initialValue: nil)
        }
        _versionsKeep = State(initialValue: seed?.versions.keep ?? .forever)
        _excludes = State(initialValue: seed?.excludes ?? BackupJob.macJunkExcludes)
        _limitEnabled = State(initialValue: seed.map { $0.removalLimit != nil } ?? true)
        _limit = State(initialValue: seed?.removalLimit ?? 100)
        _schedule = State(initialValue: BackupScheduleDraft(seed?.schedule ?? .manual))
    }

    var body: some View {
        SheetChrome(
            title: original == nil ? "New Backup" : "Edit Backup",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                FormSection(title: "Name", footer: nil) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                FormSection(title: "Folders", footer: nil) {
                    LocationPicker(label: "Back up", remoteNames: remoteNames, client: client, endpoint: $source)
                    LocationPicker(label: "To", remoteNames: remoteNames, client: client, endpoint: $destination)
                    if let problem = locationProblem {
                        Text(verbatim: problem)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Color.semantic.statusError)
                    }
                }
                modeSection
                versionsSection
                FormSection(title: "Skip", footer: nil) {
                    ExcludeListEditor(
                        patterns: $excludes,
                        lockedPattern: versionsEnabled && versionsInside ? BackupRequest.versionsExcludeRule : nil
                    )
                }
                if mode == .mirror {
                    safetySection
                }
                scheduleSection
            }
        } actions: {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(needsPreview ? "Save and Preview…" : "Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draftJob == nil)
        }
        .frame(width: 600, height: 640)
        .onChange(of: source) { _, _ in suggestName() }
        .onChange(of: destination) { _, _ in suggestName() }
    }

    private var modeSection: some View {
        FormSection(title: "Mode", footer: nil) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            Picker("", selection: $mode) {
                Text("Mirror").tag(BackupJob.Mode.mirror)
                Text("Add only").tag(BackupJob.Mode.addOnly)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Mode")
            Text(modeHelp)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modeHelp: LocalizedStringKey {
        switch mode {
        case .mirror where versionsEnabled:
            "The destination matches the source. Files you delete here are moved to versions there."
        case .mirror:
            "The destination matches the source. Files you delete here are removed there too."
        case .addOnly:
            "New and changed files are copied. Nothing is ever removed from the destination."
        }
    }

    private var versionsSection: some View {
        FormSection(title: "Versions", footer: nil) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            Toggle("Keep replaced and removed files", isOn: $versionsEnabled)
            if versionsEnabled {
                Picker("Keep them", selection: $versionsInside) {
                    Text("Inside the destination").tag(true)
                    Text("In another folder").tag(false)
                }
                .pickerStyle(.radioGroup)
                if !versionsInside {
                    LocationPicker(
                        label: "Folder",
                        remoteNames: destination?.cloudName.map { [$0] } ?? [],
                        client: client,
                        endpoint: $versionsFolder
                    )
                }
                Picker("Keep for", selection: $versionsKeep) {
                    Text("Forever").tag(BackupJob.Versions.Keep.forever)
                    Text("30 days").tag(BackupJob.Versions.Keep.days30)
                    Text("90 days").tag(BackupJob.Versions.Keep.days90)
                    Text("1 year").tag(BackupJob.Versions.Keep.year1)
                }
            } else if mode == .mirror {
                DestructiveCallout(message: "Files removed from the source will be deleted from \(destination.map(BackupRow.describe) ?? String(localized: "the destination")) for good.")
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var safetySection: some View {
        FormSection(title: "Safety", footer: nil) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            HStack(spacing: DesignSystem.Spacing.s) {
                Toggle("Stop a run that would remove more than", isOn: $limitEnabled)
                TextField("", value: $limit, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .disabled(!limitEnabled)
                    .accessibilityLabel("Removal limit")
                Text("files")
            }
            Text("A run that reaches the limit stops after removing that many files. With versions on, those files are kept in versions.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scheduleSection: some View {
        FormSection(title: "Schedule", footer: nil) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                Picker("Run", selection: $schedule.kind) {
                    ForEach(BackupScheduleDraft.Kind.allCases, id: \.self) { kind in
                        Text(verbatim: kind.label).tag(kind)
                    }
                }
                if schedule.kind.showsWeekday {
                    Picker("On", selection: $schedule.weekday) {
                        ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, name in
                            Text(verbatim: name).tag(index + 1)
                        }
                    }
                }
                if schedule.kind.showsTime {
                    DatePicker(
                        "At",
                        selection: Binding(
                            get: { schedule.timeDate() },
                            set: { schedule.setTime(from: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if OpenAtLoginNote.isShown(schedules: [schedule.schedule], openAtLoginIsOn: launchAtLogin.isEnabled) {
                OpenAtLoginNoteView(isOn: launchAtLogin.enabledBinding)
            }
        }
    }

    // MARK: - Validation and save

    private var locationProblem: String? {
        guard let source, let destination else { return nil }
        if source == destination {
            return String(localized: "The source and the destination are the same folder.")
        }
        if source.contains(destination) {
            return String(localized: "The destination is inside the source, so each run would back up the last one.")
        }
        if destination.contains(source) {
            return String(localized: "The source is inside the destination. Choose folders that don't contain each other.")
        }
        if versionsEnabled, !versionsInside {
            guard let versionsFolder else { return String(localized: "Choose a folder for versions.") }
            if versionsFolder.cloudName != destination.cloudName {
                return String(localized: "Versions must be kept in the same place as the destination.")
            }
            if versionsFolder.contains(destination) || destination.contains(versionsFolder) {
                return String(localized: "The versions folder can't be inside the destination, or contain it.")
            }
        }
        return nil
    }

    /// The edited job, or nil while it's incomplete or invalid.
    private var draftJob: BackupJob? {
        guard let source, let destination, locationProblem == nil,
              !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !limitEnabled || limit > 0 else { return nil }
        var job = original ?? BackupJob.new(source: source, destination: destination, now: Date())
        job.name = name.trimmingCharacters(in: .whitespaces)
        job.source = source
        job.destination = destination
        job.mode = mode
        job.excludes = excludes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        job.versions.enabled = versionsEnabled
        job.versions.keep = versionsKeep
        if versionsEnabled, !versionsInside, let versionsFolder {
            job.versions.location = .custom(versionsFolder)
        } else {
            job.versions.location = .insideDestination
        }
        job.removalLimit = limitEnabled ? limit : nil
        job.schedule = schedule.schedule
        return job
    }

    private var needsPreview: Bool {
        guard let original else { return true }
        guard let draftJob else { return true }
        return draftJob.fingerprint != original.fingerprint || !original.isApproved
    }

    private func save() {
        guard let job = draftJob else { return }
        let preview = needsPreview
        dismiss()
        onSave(job, preview)
    }

    private func suggestName() {
        guard name.isEmpty || name == suggestedName, let source, let destination else { return }
        let suggestion = "\(source.displayName) to \(destination.cloudName ?? destination.displayName)"
        name = suggestion
        suggestedName = suggestion
    }
}

#Preview("Mirror with versions") {
    BackupEditorSheet(
        original: BackupsFixtures.job(
            "Documents to B2",
            source: .local(path: "/Users/jonathan/Documents"),
            destination: .cloud(remote: "b2", path: "mac-backup/Documents")
        ),
        remoteNames: ["b2", "gdrive"],
        client: RcloneClient(),
        onSave: { _, _ in }
    )
    .environment(LaunchAtLoginService(refreshOnInit: false))
}

#Preview("Weekly schedule with Open at Login note") {
    BackupEditorSheet(
        original: BackupsFixtures.job(
            "Documents to B2",
            source: .local(path: "/Users/jonathan/Documents"),
            destination: .cloud(remote: "b2", path: "mac-backup/Documents")
        ) { $0.schedule = .weekly(weekday: 6, hour: 21, minute: 30) },
        remoteNames: ["b2", "gdrive"],
        client: RcloneClient(),
        onSave: { _, _ in }
    )
    .environment(LaunchAtLoginService(refreshOnInit: false))
}

#Preview("Add only, dark") {
    BackupEditorSheet(
        original: BackupsFixtures.job(
            "Photos to Drive",
            source: .local(path: "/Users/jonathan/Pictures"),
            destination: .cloud(remote: "gdrive", path: "Photos")
        ) { $0.mode = .addOnly; $0.versions.enabled = false },
        remoteNames: ["b2", "gdrive"],
        client: RcloneClient(),
        onSave: { _, _ in }
    )
    .environment(LaunchAtLoginService(refreshOnInit: false))
    .preferredColorScheme(.dark)
}
