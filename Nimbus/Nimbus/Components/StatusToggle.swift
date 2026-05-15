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

    fileprivate var visualIsOn: Bool {
        switch self {
        case .on, .unmounting: return true
        case .off, .mounting, .error: return false
        }
    }
}

/// A Switch-style toggle with explicit `.mounting` / `.unmounting` / `.error`
/// transitional states. Reference: macOS System Settings → Login Items.
///
/// Caller owns the state machine. The view is pure presentation:
/// - `.off` / `.on` render the System Settings switch look
/// - `.mounting` / `.unmounting` overlay a small ProgressView and disable tap
/// - `.error(reason:)` renders a red-tinted track with hover tooltip
///
/// Implementation note: This is a custom SwiftUI switch — not `Toggle(.switch)`
/// or `NSSwitch`. Both of those render as window-backed AppKit controls and
/// fail to rasterise through `ImageRenderer` (used by snapshot tests and any
/// preview / image-export context). A first-party SwiftUI implementation lets
/// us guarantee identical rendering in-window, in #Preview, and in fixtures,
/// while keeping the System Settings look down to the track radius and thumb
/// shadow.
struct StatusToggle: View {
    let state: StatusToggleState
    let onToggle: () -> Void

    private let trackWidth: CGFloat = 38
    private let trackHeight: CGFloat = 22
    private let thumbDiameter: CGFloat = 18
    private let thumbInset: CGFloat = 2

    var body: some View {
        ZStack {
            switchBody

            if state.isTransitioning {
                TransitioningIndicator()
            }
        }
        .frame(width: trackWidth, height: trackHeight)
        .contentShape(Capsule())
        .onTapGesture {
            guard !state.isTransitioning else { return }
            onToggle()
        }
        .help(helpText)
        .accessibilityElement()
        .accessibilityLabel(Text(state.accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var switchBody: some View {
        ZStack(alignment: state.visualIsOn ? .trailing : .leading) {
            Capsule()
                .fill(trackColor)

            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 0.5)
                .shadow(color: .black.opacity(0.10), radius: 0.5, x: 0, y: 0.5)
                .frame(width: thumbDiameter, height: thumbDiameter)
                .padding(thumbInset)
        }
        .frame(width: trackWidth, height: trackHeight)
        .opacity(state.isTransitioning ? 0.6 : 1.0)
        .animation(DesignSystem.Motion.snappy, value: state.visualIsOn)
    }

    private var trackColor: Color {
        switch state {
        case .error:
            return DesignSystem.Color.semantic.statusError
        case .on, .unmounting:
            return DesignSystem.Color.semantic.statusInfo
        case .off, .mounting:
            return DesignSystem.Color.semantic.textTertiary.opacity(0.55)
        }
    }

    private var helpText: String {
        switch state {
        case .off: return "Click to mount"
        case .mounting: return "Mounting…"
        case .on: return "Click to unmount"
        case .unmounting: return "Unmounting…"
        case .error(let reason): return "Mount error: \(reason)"
        }
    }
}

/// Mini spinner drawn entirely in SwiftUI so it rasterises through
/// `ImageRenderer`. Apple's `ProgressView()` is AppKit-backed and does not
/// render outside a window-attached context.
private struct TransitioningIndicator: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(
                DesignSystem.Color.semantic.textSecondary,
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
            )
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(rotation))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(DesignSystem.Color.semantic.surface.opacity(0.9))
            )
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

#Preview("All states") {
    VStack(alignment: .leading, spacing: 12) {
        HStack { Text("Off").frame(width: 100, alignment: .leading); StatusToggle(state: .off, onToggle: {}) }
        HStack { Text("Mounting").frame(width: 100, alignment: .leading); StatusToggle(state: .mounting, onToggle: {}) }
        HStack { Text("On").frame(width: 100, alignment: .leading); StatusToggle(state: .on, onToggle: {}) }
        HStack { Text("Unmounting").frame(width: 100, alignment: .leading); StatusToggle(state: .unmounting, onToggle: {}) }
        HStack { Text("Error").frame(width: 100, alignment: .leading); StatusToggle(state: .error(reason: "Permission denied"), onToggle: {}) }
    }
    .padding()
}
