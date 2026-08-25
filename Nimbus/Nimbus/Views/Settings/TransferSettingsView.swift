import Foundation
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

struct TransferSettingsView: View {
    @Environment(AppSettings.self) private var settings
    private let notifier: any TransferNotifying
    private let initialBandwidthLimitDraft: String?
    private let initialNotificationAuthorizationStatus: NotificationAuthorizationStatus?

    @State private var bandwidthLimitDraft = ""
    @State private var bandwidthInvalid = false
    @State private var hasInitializedBandwidthDraft = false
    @State private var notificationAuthorizationStatus: NotificationAuthorizationStatus = .notDetermined
    @State private var notificationAuthorizationError: String?
    @State private var isRequestingNotificationAuthorization = false

    init(
        notifier: any TransferNotifying = TransferNotificationService(),
        initialBandwidthLimitDraft: String? = nil,
        initialNotificationAuthorizationStatus: NotificationAuthorizationStatus? = nil
    ) {
        self.notifier = notifier
        self.initialBandwidthLimitDraft = initialBandwidthLimitDraft
        self.initialNotificationAuthorizationStatus = initialNotificationAuthorizationStatus
        _notificationAuthorizationStatus = State(
            initialValue: initialNotificationAuthorizationStatus ?? .notDetermined
        )
    }

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                TransferPerformanceSection(
                    concurrentTransfers: concurrentTransfersBinding,
                    bandwidthLimitDraft: $bandwidthLimitDraft,
                    bandwidthInvalid: bandwidthInvalid,
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
        .accessibilityIdentifier("settings-transfers")
        .onAppear(perform: initializeBandwidthLimitDraft)
        .task {
            guard initialNotificationAuthorizationStatus == nil else { return }
            notificationAuthorizationStatus = await notifier.authorizationStatus()
        }
    }

    private var concurrentTransfersBinding: Binding<Int> {
        Binding(
            get: { min(max(settings.concurrentTransfers, 1), 32) },
            set: { settings.concurrentTransfers = min(max($0, 1), 32) }
        )
    }

    private var notificationModeBinding: Binding<TransferNotificationMode> {
        Binding(
            get: { settings.transferNotificationMode },
            set: updateNotificationMode
        )
    }

    private func initializeBandwidthLimitDraft() {
        guard !hasInitializedBandwidthDraft else { return }
        bandwidthLimitDraft = initialBandwidthLimitDraft ?? settings.bandwidthLimit
        bandwidthInvalid = !BandwidthLimitValidator.validate(bandwidthLimitDraft)
        hasInitializedBandwidthDraft = true
    }

    private func commitBandwidthLimit() {
        let trimmed = bandwidthLimitDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BandwidthLimitValidator.validate(trimmed) else {
            bandwidthInvalid = true
            return
        }

        bandwidthLimitDraft = trimmed
        bandwidthInvalid = false
        settings.bandwidthLimit = trimmed
    }

    private func updateNotificationMode(_ mode: TransferNotificationMode) {
        settings.transferNotificationMode = mode
        notificationAuthorizationError = nil

        guard mode != .off else { return }

        Task { @MainActor in
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
    @Binding var concurrentTransfers: Int
    @Binding var bandwidthLimitDraft: String
    let bandwidthInvalid: Bool
    let commitBandwidthLimit: () -> Void
    @FocusState private var isBandwidthLimitFocused: Bool

    var body: some View {
        FormSection(
            title: "Performance",
            footer: "Higher concurrency improves throughput but uses more memory."
        ) {
            FormRow(label: "Concurrent Transfers", help: nil) {
                Stepper(value: $concurrentTransfers, in: 1...32) {
                    Text("\(concurrentTransfers)")
                }
                .frame(width: 140, alignment: .trailing)
                .accessibilityLabel("Concurrent Transfers")
            }
            FormRow(
                label: "Bandwidth Limit",
                help: "Leave empty for unlimited. Use a positive number with an optional k, M, G, or T suffix."
            ) {
                TextField("Unlimited", text: $bandwidthLimitDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .focused($isBandwidthLimitFocused)
                    .onSubmit(commitBandwidthLimit)
                    .onChange(of: isBandwidthLimitFocused) { _, isFocused in
                        if !isFocused {
                            commitBandwidthLimit()
                        }
                    }
                    .accessibilityLabel("Bandwidth Limit")
                    .accessibilityHint(
                        bandwidthInvalid
                            ? "Enter a positive number, optionally followed by k, M, G, or T."
                            : "Leave empty for unlimited."
                    )
            }
            if bandwidthInvalid {
                Text("Enter a positive number, optionally followed by k, M, G, or T.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.statusError)
                    .accessibilityLabel("Bandwidth limit error: Enter a positive number, optionally followed by k, M, G, or T.")
                    .padding(.top, DesignSystem.Spacing.xs)
            }
        }
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
        FormSection(title: "Behavior", footer: nil) {
            FormRow(label: "File Conflicts", help: "Used as the initial choice for new copy operations.") {
                Picker("File Conflicts", selection: $conflictPolicy) {
                    Text("Rename").tag(ConflictPolicy.rename)
                    Text("Skip").tag(ConflictPolicy.skip)
                    Text("Overwrite").tag(ConflictPolicy.overwrite)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 140, alignment: .trailing)
                .accessibilityLabel("File Conflicts")
            }
            FormRow(label: "Transfer Notifications", help: nil) {
                Picker("Transfer Notifications", selection: $notificationMode) {
                    Text("Failures Only").tag(TransferNotificationMode.failuresOnly)
                    Text("All Transfers").tag(TransferNotificationMode.allTransfers)
                    Text("Off").tag(TransferNotificationMode.off)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 140, alignment: .trailing)
                .accessibilityLabel("Transfer Notifications")
            }
            if notificationMode != .off {
                NotificationAuthorizationStatusRow(
                    status: notificationAuthorizationStatus,
                    error: notificationAuthorizationError,
                    isRequestingAuthorization: isRequestingNotificationAuthorization
                )
            }
            FormRow(label: "Keep Transfer History", help: nil) {
                Picker("Keep Transfer History", selection: $historyRetention) {
                    Text("7 Days").tag(TransferHistoryRetention.sevenDays)
                    Text("30 Days").tag(TransferHistoryRetention.thirtyDays)
                    Text("Forever").tag(TransferHistoryRetention.forever)
                    Text("Until Nimbus Quits").tag(TransferHistoryRetention.untilQuit)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160, alignment: .trailing)
                .accessibilityLabel("Keep Transfer History")
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
                Text("Requesting notification permission...")
            } else if status == .denied {
                Label("Disabled in System Settings", systemImage: "bell.slash")
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                Spacer()
                Link("Open Notification Settings", destination: notificationSettingsURL)
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
        .accessibilityElement(children: .combine)
    }

    private var notificationSettingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
    }
}

#Preview {
    TransferSettingsView()
        .environment(AppSettings())
        .frame(width: 680, height: 520)
}
