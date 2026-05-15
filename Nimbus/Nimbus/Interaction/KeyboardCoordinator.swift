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

    private struct Binding {
        let key: KeyEquivalent
        let modifiers: EventModifiers
        let scope: Scope
        let perform: () -> Void
    }

    private var bindings: [Binding] = []

    // Type-to-select buffer state
    private var buffer: String = ""
    private var lastInputTime: TimeInterval = 0
    private let bufferTimeout: TimeInterval = 0.5

    func register(_ key: KeyEquivalent, modifiers: EventModifiers = [], scope: Scope, perform: @escaping () -> Void) {
        bindings.append(Binding(key: key, modifiers: modifiers, scope: scope, perform: perform))
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
}
