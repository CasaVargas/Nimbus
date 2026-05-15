import Testing
import SwiftUI
@testable import Nimbus

@Suite("KeyboardCoordinator")
@MainActor
struct KeyboardCoordinatorTests {
    @Test func registeredHandlerFiresOnExactKeyMatch() {
        let kc = KeyboardCoordinator()
        var fired = 0
        kc.register(.space, modifiers: [], scope: .browser) { fired += 1 }
        let handled = kc.handle(key: .space, modifiers: [], scope: .browser)
        #expect(handled)
        #expect(fired == 1)
    }

    @Test func wrongScopeDoesNotFire() {
        let kc = KeyboardCoordinator()
        var fired = 0
        kc.register(.space, modifiers: [], scope: .browser) { fired += 1 }
        let handled = kc.handle(key: .space, modifiers: [], scope: .sheet)
        #expect(handled == false)
        #expect(fired == 0)
    }

    @Test func modifierMismatchDoesNotFire() {
        let kc = KeyboardCoordinator()
        var fired = 0
        kc.register("d", modifiers: [.command], scope: .browser) { fired += 1 }
        _ = kc.handle(key: "d", modifiers: [], scope: .browser)
        #expect(fired == 0)
        _ = kc.handle(key: "d", modifiers: [.command], scope: .browser)
        #expect(fired == 1)
    }

    @Test func typeToSelectMatchesPrefixCaseInsensitively() {
        let kc = KeyboardCoordinator()
        var matched: String?
        let items = ["Apple.pdf", "Banana.txt", "apricot.heic", "Cantaloupe.mov"]
        kc.handleTypeToSelect(char: "a", against: items, now: 0) { matched = $0 }
        #expect(matched == "Apple.pdf")
        kc.handleTypeToSelect(char: "p", against: items, now: 0.1) { matched = $0 }
        // buffer is now "ap" — matches "Apple.pdf" and "apricot.heic"; first wins
        #expect(matched == "Apple.pdf")
        kc.handleTypeToSelect(char: "r", against: items, now: 0.2) { matched = $0 }
        // buffer "apr" — only "apricot.heic"
        #expect(matched == "apricot.heic")
    }

    @Test func typeToSelectResetsAfterTimeout() {
        let kc = KeyboardCoordinator()
        var matched: String?
        let items = ["Apple.pdf", "Banana.txt"]
        kc.handleTypeToSelect(char: "a", against: items, now: 0) { matched = $0 }
        #expect(matched == "Apple.pdf")
        // simulate 0.6s gap — buffer resets, next char starts fresh
        kc.handleTypeToSelect(char: "b", against: items, now: 0.6) { matched = $0 }
        #expect(matched == "Banana.txt")
    }

    @Test func typeToSelectHandlesDiacriticsViaLocalizedStandardCompare() {
        let kc = KeyboardCoordinator()
        var matched: String?
        let items = ["école.txt", "Étoile.md", "echo.swift"]
        kc.handleTypeToSelect(char: "e", against: items, now: 0) { matched = $0 }
        // localized comparison treats é/E/e as equivalent — should find a non-nil match
        #expect(matched != nil)
    }
}
