import Foundation
import RcloneKit
import SwiftUI

enum BandwidthLimitValidator {
    static func validate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let numericValue: String
        if let suffix = trimmed.last, "kMGT".contains(suffix) {
            numericValue = String(trimmed.dropLast())
        } else {
            numericValue = trimmed
        }

        guard numericValue.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let number = Decimal(string: numericValue, locale: Locale(identifier: "en_US_POSIX")) else {
            return false
        }

        return number > 0
    }
}

/// The speed-limit menu. rclone `--bwlimit` takes bytes per second with
/// binary suffixes ("5M" = 5 MiB/s); the menu says "MB/s" because that's how
/// people read speeds. Anything that isn't a preset is Custom, so a value set
/// by hand (or by an older Nimbus) is shown as-is, never silently changed.
enum SpeedLimitChoice: Hashable, CaseIterable {
    case unlimited, mb1, mb5, mb10, mb25, mb50, custom

    static let presets: [SpeedLimitChoice] = [.unlimited, .mb1, .mb5, .mb10, .mb25, .mb50]

    /// The stored rclone value for a preset; nil for `.custom`.
    var value: String? {
        switch self {
        case .unlimited: ""
        case .mb1: "1M"
        case .mb5: "5M"
        case .mb10: "10M"
        case .mb25: "25M"
        case .mb50: "50M"
        case .custom: nil
        }
    }

    var title: String {
        switch self {
        case .unlimited: "No limit"
        case .mb1: "1 MB/s"
        case .mb5: "5 MB/s"
        case .mb10: "10 MB/s"
        case .mb25: "25 MB/s"
        case .mb50: "50 MB/s"
        case .custom: "Custom…"
        }
    }

    init(storedValue: String) {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self = Self.presets.first { $0.value == trimmed } ?? .custom
    }
}

@MainActor
protocol TransferRuntimeConfiguring {
    func setBandwidthLimit(rate: String) async throws -> BandwidthLimitResponse
    func setConcurrentTransfers(_ transfers: Int) async throws
}

extension RcloneClient: TransferRuntimeConfiguring {}

/// Applies transfer preferences to the live daemon before persisting them.
/// This ordering keeps UserDefaults and the active rclone process consistent:
/// a failed RC call leaves the last known-good persisted preference untouched.
@MainActor
enum TransferRuntimeSettings {
    static func applyBandwidthLimit(
        _ bandwidthLimit: String,
        settings: AppSettings,
        runtime: any TransferRuntimeConfiguring
    ) async throws {
        let persistedValue = bandwidthLimit.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await runtime.setBandwidthLimit(rate: persistedValue.isEmpty ? "off" : persistedValue)
        settings.bandwidthLimit = persistedValue
    }

    static func applyConcurrentTransfers(
        _ concurrentTransfers: Int,
        settings: AppSettings,
        runtime: any TransferRuntimeConfiguring
    ) async throws {
        let clampedValue = min(max(concurrentTransfers, 1), 32)
        try await runtime.setConcurrentTransfers(clampedValue)
        settings.concurrentTransfers = clampedValue
    }
}

struct TransferSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(\.transferNotifier) private var environmentNotifier
    private let notifier: (any TransferNotifying)?
    private let runtime: (any TransferRuntimeConfiguring)?
    private let initialBandwidthLimitDraft: String?
    private let initialNotificationAuthorizationStatus: NotificationAuthorizationStatus?

    @State private var bandwidthLimitDraft = ""
    @State private var speedChoice: SpeedLimitChoice = .unlimited
    @State private var bandwidthInvalid = false
    @State private var bandwidthRuntimeError: String?
    @State private var concurrentTransfersRuntimeError: String?
    @State private var isApplyingBandwidthLimit = false
    @State private var isApplyingConcurrentTransfers = false
    @State private var hasInitializedBandwidthDraft = false
    @State private var notificationAuthorizationStatus: NotificationAuthorizationStatus = .notDetermined
    @State private var notificationAuthorizationError: String?
    @State private var isRequestingNotificationAuthorization = false

    init(
        notifier: (any TransferNotifying)? = nil,
        runtime: (any TransferRuntimeConfiguring)? = nil,
        initialBandwidthLimitDraft: String? = nil,
        initialNotificationAuthorizationStatus: NotificationAuthorizationStatus? = nil
    ) {
        self.notifier = notifier
        self.runtime = runtime
        self.initialBandwidthLimitDraft = initialBandwidthLimitDraft
        self.initialNotificationAuthorizationStatus = initialNotificationAuthorizationStatus
        _notificationAuthorizationStatus = State(
            initialValue: initialNotificationAuthorizationStatus ?? .notDetermined
        )
        // A draft passed in is known now, so set the speed menu's state here
        // rather than in onAppear: the Custom field appears or not depending
        // on it, and the first frame must already be right.
        if let initialBandwidthLimitDraft {
            _bandwidthLimitDraft = State(initialValue: initialBandwidthLimitDraft)
            _speedChoice = State(initialValue: SpeedLimitChoice(storedValue: initialBandwidthLimitDraft))
            _bandwidthInvalid = State(initialValue: !BandwidthLimitValidator.validate(initialBandwidthLimitDraft))
            _hasInitializedBandwidthDraft = State(initialValue: true)
        }
    }

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                TransferPerformanceSection(
                    concurrentTransfers: min(max(settings.concurrentTransfers, 1), 32),
                    updateConcurrentTransfers: updateConcurrentTransfers,
                    concurrentTransfersRuntimeError: concurrentTransfersRuntimeError,
                    isApplyingConcurrentTransfers: isApplyingConcurrentTransfers,
                    speedChoice: Binding(get: { speedChoice }, set: chooseSpeed),
                    bandwidthLimitDraft: $bandwidthLimitDraft,
                    bandwidthInvalid: bandwidthInvalid,
                    bandwidthRuntimeError: bandwidthRuntimeError,
                    isApplyingBandwidthLimit: isApplyingBandwidthLimit,
                    commitBandwidthLimit: commitBandwidthLimit
                )
                TransferBehaviorSection(
                    conflictPolicy: $settings.defaultConflictPolicy,
                    notificationMode: notificationModeBinding,
                    historyRetention: $settings.transferHistoryRetention,
                    notificationAuthorizationStatus: notificationAuthorizationStatus,
                    notificationAuthorizationError: notificationAuthorizationError,
                    isRequestingNotificationAuthorization: isRequestingNotificationAuthorization
                )
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.top)
        .accessibilityIdentifier("settings-transfers")
        .onAppear(perform: initializeBandwidthLimitDraft)
        .task {
            guard initialNotificationAuthorizationStatus == nil else { return }
            notificationAuthorizationStatus = await activeNotifier.authorizationStatus()
        }
    }

    private var notificationModeBinding: Binding<TransferNotificationMode> {
        Binding(
            get: { settings.transferNotificationMode },
            set: updateNotificationMode
        )
    }

    private var activeNotifier: any TransferNotifying {
        notifier ?? environmentNotifier ?? TransferNotificationService()
    }

    private func initializeBandwidthLimitDraft() {
        guard !hasInitializedBandwidthDraft else { return }
        bandwidthLimitDraft = initialBandwidthLimitDraft ?? settings.bandwidthLimit
        speedChoice = SpeedLimitChoice(storedValue: bandwidthLimitDraft)
        bandwidthInvalid = !BandwidthLimitValidator.validate(bandwidthLimitDraft)
        hasInitializedBandwidthDraft = true
    }

    /// A preset applies at once; Custom reveals the text field and waits for
    /// the user to type (starting empty if the old value was a preset).
    private func chooseSpeed(_ choice: SpeedLimitChoice) {
        speedChoice = choice
        if let value = choice.value {
            bandwidthLimitDraft = value
            commitBandwidthLimit()
        } else if SpeedLimitChoice(storedValue: bandwidthLimitDraft) != .custom {
            bandwidthLimitDraft = ""
            bandwidthInvalid = false
        }
    }

    private func commitBandwidthLimit() {
        let trimmed = bandwidthLimitDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BandwidthLimitValidator.validate(trimmed) else {
            bandwidthInvalid = true
            return
        }

        bandwidthLimitDraft = trimmed
        bandwidthInvalid = false
        bandwidthRuntimeError = nil
        isApplyingBandwidthLimit = true

        let runtime = runtime ?? daemon.client
        Task { @MainActor in
            defer { isApplyingBandwidthLimit = false }
            do {
                try await TransferRuntimeSettings.applyBandwidthLimit(
                    trimmed,
                    settings: settings,
                    runtime: runtime
                )
            } catch {
                bandwidthRuntimeError = "Couldn't apply the speed limit: \(error.localizedDescription)"
            }
        }
    }

    private func updateConcurrentTransfers(_ concurrentTransfers: Int) {
        concurrentTransfersRuntimeError = nil
        isApplyingConcurrentTransfers = true

        let runtime = runtime ?? daemon.client
        Task { @MainActor in
            defer { isApplyingConcurrentTransfers = false }
            do {
                try await TransferRuntimeSettings.applyConcurrentTransfers(
                    concurrentTransfers,
                    settings: settings,
                    runtime: runtime
                )
            } catch {
                concurrentTransfersRuntimeError = "Couldn't change copies at once: \(error.localizedDescription)"
            }
        }
    }

    private func updateNotificationMode(_ mode: TransferNotificationMode) {
        settings.transferNotificationMode = mode
        notificationAuthorizationError = nil

        guard mode != .off else { return }

        Task { @MainActor in
            let notifier = activeNotifier
            let status = await notifier.authorizationStatus()
            notificationAuthorizationStatus = status

            guard status == .notDetermined, !isRequestingNotificationAuthorization else { return }
            isRequestingNotificationAuthorization = true
            defer { isRequestingNotificationAuthorization = false }

            do {
                notificationAuthorizationStatus = try await notifier.requestAuthorization() ? .authorized : .denied
            } catch {
                notificationAuthorizationError = error.localizedDescription
            }
        }
    }
}

private struct TransferPerformanceSection: View {
    let concurrentTransfers: Int
    let updateConcurrentTransfers: (Int) -> Void
    let concurrentTransfersRuntimeError: String?
    let isApplyingConcurrentTransfers: Bool
    @Binding var speedChoice: SpeedLimitChoice
    @Binding var bandwidthLimitDraft: String
    let bandwidthInvalid: Bool
    let bandwidthRuntimeError: String?
    let isApplyingBandwidthLimit: Bool
    let commitBandwidthLimit: () -> Void
    @FocusState private var isBandwidthLimitFocused: Bool

    private static let customHint = "Enter a speed like 500k, 2M or 1.5G (bytes per second)."

    var body: some View {
        FormSection(title: "Speed", footer: nil) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                FormRow(
                    label: "Copies at once",
                    help: "More is faster on a fast connection; fewer is gentler on your Mac and network."
                ) {
                    Stepper(
                        value: Binding(
                            get: { concurrentTransfers },
                            set: { updateConcurrentTransfers($0) }
                        ),
                        in: 1...32
                    ) {
                        Text("\(concurrentTransfers)")
                            .monospacedDigit()
                    }
                    .frame(width: 140, alignment: .trailing)
                    .disabled(isApplyingConcurrentTransfers)
                    .accessibilityLabel("Copies at once")
                    .accessibilityValue("\(concurrentTransfers)")
                }
                if let concurrentTransfersRuntimeError {
                    runtimeError(concurrentTransfersRuntimeError)
                }
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                FormRow(label: "Speed limit", help: nil) {
                    Picker("Speed limit", selection: $speedChoice) {
                        ForEach(SpeedLimitChoice.presets, id: \.self) { choice in
                            Text(verbatim: choice.title).tag(choice)
                        }
                        Divider()
                        Text(verbatim: SpeedLimitChoice.custom.title).tag(SpeedLimitChoice.custom)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140, alignment: .trailing)
                    .disabled(isApplyingBandwidthLimit)
                    .accessibilityLabel("Speed limit")
                }
                if speedChoice == .custom {
                    HStack {
                        Spacer()
                        TextField("e.g. 2M", text: $bandwidthLimitDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .focused($isBandwidthLimitFocused)
                            .disabled(isApplyingBandwidthLimit)
                            .onSubmit(commitBandwidthLimit)
                            .onChange(of: isBandwidthLimitFocused) { _, isFocused in
                                if !isFocused { commitBandwidthLimit() }
                            }
                            .accessibilityLabel("Custom speed limit")
                            .accessibilityHint(Self.customHint)
                    }
                    Text(verbatim: Self.customHint)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(bandwidthInvalid ? DesignSystem.Color.semantic.statusError
                                                          : DesignSystem.Color.semantic.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let bandwidthRuntimeError {
                    runtimeError(bandwidthRuntimeError)
                }
            }
        }
    }

    private func runtimeError(_ message: String) -> some View {
        Text(verbatim: message)
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Color.semantic.statusError)
            .accessibilityLabel("Transfer setting error: \(message)")
    }
}

private struct TransferBehaviorSection: View {
    @Binding var conflictPolicy: ConflictPolicy
    @Binding var notificationMode: TransferNotificationMode
    @Binding var historyRetention: TransferHistoryRetention
    let notificationAuthorizationStatus: NotificationAuthorizationStatus
    let notificationAuthorizationError: String?
    let isRequestingNotificationAuthorization: Bool

    var body: some View {
        FormSection(title: "Copying", footer: nil) {
            FormRow(label: "If a file already exists", help: "You can still choose differently for each copy.") {
                Picker("If a file already exists", selection: $conflictPolicy) {
                    Text("Keep Both").tag(ConflictPolicy.rename)
                    Text("Skip").tag(ConflictPolicy.skip)
                    Text("Replace").tag(ConflictPolicy.overwrite)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 140, alignment: .trailing)
                .accessibilityLabel("If a file already exists")
            }
        }
        FormSection(title: "Notifications and activity", footer: nil) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                FormRow(label: "Notify me", help: nil) {
                    Picker("Notify me", selection: $notificationMode) {
                        Text("When something fails").tag(TransferNotificationMode.failuresOnly)
                        Text("After every copy").tag(TransferNotificationMode.allTransfers)
                        Text("Never").tag(TransferNotificationMode.off)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 190, alignment: .trailing)
                    .accessibilityLabel("Notify me")
                }
                if notificationMode != .off,
                   notificationAuthorizationStatus == .denied
                    || notificationAuthorizationError != nil
                    || isRequestingNotificationAuthorization {
                    NotificationAuthorizationStatusRow(
                        status: notificationAuthorizationStatus,
                        error: notificationAuthorizationError,
                        isRequestingAuthorization: isRequestingNotificationAuthorization
                    )
                }
            }
            FormRow(label: "Keep activity for", help: nil) {
                Picker("Keep activity for", selection: $historyRetention) {
                    Text("7 days").tag(TransferHistoryRetention.sevenDays)
                    Text("30 days").tag(TransferHistoryRetention.thirtyDays)
                    Text("Until Nimbus quits").tag(TransferHistoryRetention.untilQuit)
                    Text("Forever").tag(TransferHistoryRetention.forever)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 190, alignment: .trailing)
                .accessibilityLabel("Keep activity for")
            }
        }
    }
}

private struct NotificationAuthorizationStatusRow: View {
    let status: NotificationAuthorizationStatus
    let error: String?
    let isRequestingAuthorization: Bool

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            if isRequestingAuthorization {
                ProgressView()
                    .controlSize(.small)
                Text("Asking for permission to notify…")
            } else if status == .denied {
                Label("Notifications are off for Nimbus in System Settings", systemImage: "bell.slash")
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                Spacer()
                Link("Turn On…", destination: notificationSettingsURL)
            } else if let error {
                Label {
                    Text(verbatim: error)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(DesignSystem.Color.semantic.statusError)
            }
        }
        .font(DesignSystem.Typography.caption)
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    private var notificationSettingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
    }
}

#Preview {
    TransferSettingsView(initialNotificationAuthorizationStatus: .authorized)
        .environment(AppSettings())
        .environment(RcloneDaemon())
        .frame(width: 680, height: 560)
}
