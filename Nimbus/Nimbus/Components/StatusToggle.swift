import SwiftUI

enum StatusToggleState: Equatable, Sendable {
    case off
    case mounting
    case on
    case unmounting
    case error(reason: String)

    var accessibilityLabel: String {
        switch self {
        case .off: return "Off"
        case .mounting: return "Mounting"
        case .on: return "On"
        case .unmounting: return "Unmounting"
        case .error(let reason): return "Error: \(reason)"
        }
    }

    var isTransitioning: Bool {
        switch self {
        case .mounting, .unmounting: return true
        default: return false
        }
    }

    /// Visual on-state for the underlying Toggle. `.unmounting` shows as "on"
    /// (we're transitioning away from on), `.mounting` shows as "off".
    var visualIsOn: Bool {
        switch self {
        case .on, .unmounting: return true
        case .off, .mounting, .error: return false
        }
    }
}

/// A Switch-style toggle with explicit `.mounting` / `.unmounting` / `.error`
/// transitional states. Reference: macOS System Settings → Login Items.
///
/// Uses SwiftUI's native `Toggle(.switch)` for full Apple-grade fidelity:
/// system accent color, focus ring, VoiceOver "switch" trait, all
/// automatically inherited from the system control. Custom variants
/// (transitioning spinner, error tint) layer on top without replacing
/// the underlying control.
///
/// Caller owns the state machine. The view is pure presentation:
/// - `.off` / `.on` → native Toggle in default appearance
/// - `.mounting` / `.unmounting` → Toggle disabled with overlay ProgressView
/// - `.error(reason:)` → Toggle tinted red, hover tooltip shows reason
struct StatusToggle: View {
    let state: StatusToggleState
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { state.visualIsOn },
            set: { _ in
                guard !state.isTransitioning else { return }
                onToggle()
            }
        )) {
            EmptyView()
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .labelsHidden()
        .disabled(state.isTransitioning)
        .tint(tintColor)
        .overlay(alignment: .center) {
            if state.isTransitioning {
                ProgressView()
                    .controlSize(.mini)
                    .allowsHitTesting(false)
            }
        }
        .help(helpText)
        .accessibilityLabel(state.accessibilityLabel)
    }

    private var tintColor: Color {
        switch state {
        case .error: return DesignSystem.Color.semantic.statusError
        default:     return .accentColor   // System accent — matches HIG
        }
    }

    private var helpText: String {
        switch state {
        case .off: return "Click to mount"
        case .mounting: return "Mounting, please wait"
        case .on: return "Click to unmount"
        case .unmounting: return "Unmounting, please wait"
        case .error(let reason): return "Mount error: \(reason)"
        }
    }
}

#Preview("Status Toggle") {
    VStack(spacing: 16) {
        StatusToggle(state: .off, onToggle: {})
        StatusToggle(state: .mounting, onToggle: {})
        StatusToggle(state: .on, onToggle: {})
        StatusToggle(state: .unmounting, onToggle: {})
        StatusToggle(state: .error(reason: "Permission denied"), onToggle: {})
    }
    .padding(40)
}
