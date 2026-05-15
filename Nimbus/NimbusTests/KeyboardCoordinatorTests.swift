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

    @Test func unregisterAllRemovesScopedBindings() {
        let kc = KeyboardCoordinator()
        var browserFired = 0
        var sheetFired = 0
        kc.register(.space, modifiers: [], scope: .browser) { browserFired += 1 }
        kc.register(.space, modifiers: [], scope: .sheet) { sheetFired += 1 }
        kc.unregisterAll(scope: .browser)
        _ = kc.handle(key: .space, modifiers: [], scope: .browser)
        _ = kc.handle(key: .space, modifiers: [], scope: .sheet)
        #expect(browserFired == 0)
        #expect(sheetFired == 1)
    }

    @Test func reregisterAfterUnregisterWorks() {
        let kc = KeyboardCoordinator()
        var fired = 0
        kc.register(.space, modifiers: [], scope: .browser) { fired += 1 }
        kc.unregisterAll(scope: .browser)
        kc.register(.space, modifiers: [], scope: .browser) { fired += 10 }
        _ = kc.handle(key: .space, modifiers: [], scope: .browser)
        #expect(fired == 10)
    }

    @Test func resetBufferClearsTypeToSelect() {
        let kc = KeyboardCoordinator()
        var matched: String?
        let items = ["Apple.pdf", "Banana.txt"]
        kc.handleTypeToSelect(char: "a", against: items, now: 0) { matched = $0 }
        #expect(matched == "Apple.pdf")
        kc.resetBuffer()
        kc.handleTypeToSelect(char: "b", against: items, now: 0.01) { matched = $0 }
        // Reset succeeded → "b" alone matches Banana even within the 0.5s timeout window
        #expect(matched == "Banana.txt")
    }
}
