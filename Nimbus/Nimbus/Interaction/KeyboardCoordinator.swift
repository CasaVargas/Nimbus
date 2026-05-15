import SwiftUI
import Observation

@Observable
@MainActor
final class KeyboardCoordinator {
    enum Scope: Hashable, Sendable {
        case browser
        case sheet
        case quickLook
    }

    private struct KeyBinding {
        let key: KeyEquivalent
        let modifiers: EventModifiers
        let scope: Scope
        let perform: () -> Void
    }

    private var bindings: [KeyBinding] = []

    // Type-to-select buffer state
    private var buffer: String = ""
    private var lastInputTime: TimeInterval = -.infinity
    private let bufferTimeout: TimeInterval = 0.5

    /// Registers a key binding. Duplicate `(key.character, modifiers, scope)` is a programmer error
    /// and traps in debug — pick `unregisterAll(scope:)` and re-register if you need to rebind.
    func register(_ key: KeyEquivalent, modifiers: EventModifiers = [], scope: Scope, perform: @escaping () -> Void) {
        precondition(
            !bindings.contains(where: { $0.key.character == key.character && $0.modifiers == modifiers && $0.scope == scope }),
            "duplicate keyboard binding for \(key.character) modifiers=\(modifiers.rawValue) scope=\(scope)"
        )
        bindings.append(KeyBinding(key: key, modifiers: modifiers, scope: scope, perform: perform))
    }

    /// Removes all bindings for the given scope. Call when a view's lifecycle ends to drop
    /// captured handler closures and allow re-registration on next mount.
    func unregisterAll(scope: Scope) {
        bindings.removeAll { $0.scope == scope }
    }

    @discardableResult
    func handle(key: KeyEquivalent, modifiers: EventModifiers, scope: Scope) -> Bool {
        for b in bindings where b.scope == scope
            && b.key.character == key.character
            && b.modifiers == modifiers {
            b.perform()
            return true
        }
        return false
    }

    /// Type-to-select. Accumulates characters within `bufferTimeout` of each other.
    /// Matches case- and diacritic-insensitively against item ordering (anchored prefix).
    func handleTypeToSelect(
        char: Character,
        against items: [String],
        now: TimeInterval = Date().timeIntervalSinceReferenceDate,
        onMatch: (String) -> Void
    ) {
        if now - lastInputTime > bufferTimeout {
            buffer = ""
        }
        buffer.append(char)
        lastInputTime = now

        let needle = buffer
        if let hit = items.first(where: {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }) {
            onMatch(hit)
        }
    }

    /// Clears the type-to-select buffer immediately. Call on focus loss, sheet present,
    /// or other moments where preserving the half-typed prefix would be confusing.
    func resetBuffer() {
        buffer = ""
        lastInputTime = -.infinity
    }
}
