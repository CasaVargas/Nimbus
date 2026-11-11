import Foundation
import Observation

/// Drives the "Lock with Keychain" switch in Settings > Advanced (#67).
/// The file on disk is the source of truth; this model only mirrors it.
@Observable
@MainActor
final class ConfigEncryptionModel {
    enum Activity: Equatable {
        case idle
        case locking
        case unlocking
    }

    /// nil until the first read finishes.
    private(set) var state: ConfigEncryptionState?
    private(set) var activity: Activity = .idle
    private(set) var errorMessage: String?
    let password: KeychainConfigPassword

    @ObservationIgnored private let readsLiveState: Bool

    init(
        state: ConfigEncryptionState? = nil,
        password: KeychainConfigPassword = .standard,
        readsLiveState: Bool = true
    ) {
        self.state = state
        self.password = password
        self.readsLiveState = readsLiveState
    }

    var isLocked: Bool { state == .locked }

    /// Why the switch can't move right now, or nil when it can. Running NFS
    /// servers and the daemon loaded the config as it was, and would write it
    /// back in that form on their next token refresh.
    static func blockReason(
        state: ConfigEncryptionState?,
        connectedNetworkDrives: Int,
        transfersRunning: Bool,
        backupsRunning: Bool
    ) -> String? {
        switch state {
        case nil:
            return nil
        case .lockedWithoutKey:
            return ConfigEncryptionState.lockedWithoutKeyMessage
        case .plain, .locked:
            break
        }
        if connectedNetworkDrives > 0 {
            return "Disconnect your network drives first."
        }
        if transfersRunning || backupsRunning {
            return "Wait for transfers and backups to finish."
        }
        return nil
    }

    func refresh(binaryPath: String) async {
        guard readsLiveState, LaunchContext.current.managesSystemProcesses else { return }
        let password = password
        state = await Task.detached(priority: .userInitiated) {
            ConfigEncryptionState.read(binaryPath: binaryPath, password: password)
        }.value
    }

    /// Stops the engine, rewrites rclone.conf, starts the engine again. The
    /// engine always restarts, even when the change failed and was rolled
    /// back, so a failure never leaves the user without their clouds.
    func setLocked(
        _ locked: Bool,
        binaryPath: String,
        stopEngine: () -> Void,
        startEngine: () async -> Void
    ) async {
        guard activity == .idle, locked != isLocked else { return }
        activity = locked ? .locking : .unlocking
        errorMessage = nil
        stopEngine()

        let password = password
        let failure: String? = await Task.detached(priority: .userInitiated) {
            do {
                guard let url = RcloneConfigFile.locate(binaryPath: binaryPath) else {
                    throw ConfigEncryptionError.configNotFound
                }
                let encryptor = ConfigEncryptor(binaryPath: binaryPath, configURL: url, password: password)
                if locked { try encryptor.enable() } else { try encryptor.disable() }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value

        await startEngine()
        state = await Task.detached(priority: .userInitiated) {
            ConfigEncryptionState.read(binaryPath: binaryPath, password: password)
        }.value
        errorMessage = failure
        activity = .idle
    }
}
