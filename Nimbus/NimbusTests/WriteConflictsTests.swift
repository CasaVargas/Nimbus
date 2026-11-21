import Foundation
import Testing
@testable import Nimbus

@Suite("WriteConflicts")
struct WriteConflictsTests {
    // MARK: - ItemVersionBytes

    @Test func fileContentVersionMatchesRawSecondsPlusSizeSuffix() {
        let s: TimeInterval = 1_763_711_880.5
        let expectedKnown = withUnsafeBytes(of: s) { Data($0) } + Data(ItemSize.contentVersionSuffix(listed: 4096))
        #expect(ItemVersionBytes.content(seconds: s, size: 4096, isDir: false) == expectedKnown)

        let expectedUnknown = withUnsafeBytes(of: s) { Data($0) } + Data(ItemSize.contentVersionSuffix(listed: -1))
        #expect(ItemVersionBytes.content(seconds: s, size: -1, isDir: false) == expectedUnknown)
        #expect(expectedUnknown != expectedKnown)
    }

    @Test func folderContentVersionHasNoSizeSuffix() {
        let s: TimeInterval = 1_763_711_880.5
        let expected = withUnsafeBytes(of: s) { Data($0) }
        #expect(ItemVersionBytes.content(seconds: s, size: -1, isDir: true) == expected)
        #expect(ItemVersionBytes.content(seconds: s, size: 0, isDir: true) == expected)
    }

    @Test func nilSecondsProducesSingleZeroBytePlusFileSuffix() {
        #expect(ItemVersionBytes.seconds(nil) == Data([0]))
        #expect(ItemVersionBytes.content(seconds: nil, size: 128, isDir: false) == Data([0]))
        #expect(ItemVersionBytes.content(seconds: nil, size: -1, isDir: false) == Data([0, 1]))
        #expect(ItemVersionBytes.content(seconds: nil, size: -1, isDir: true) == Data([0]))
    }

    // MARK: - EditConflict

    @Test func decideCoversAllFourRules() {
        let v1 = Data([1, 2, 3])
        let v2 = Data([4, 5, 6])

        #expect(EditConflict.decide(baseContentVersion: v1, baseIsBeforeFirstSync: false, serverContentVersion: nil) == .uploadUnlessDifferent)
        #expect(EditConflict.decide(baseContentVersion: v1, baseIsBeforeFirstSync: true, serverContentVersion: nil) == .uploadUnlessDifferent)
        #expect(EditConflict.decide(baseContentVersion: v1, baseIsBeforeFirstSync: true, serverContentVersion: v2) == .uploadUnlessDifferent)
        #expect(EditConflict.decide(baseContentVersion: v1, baseIsBeforeFirstSync: false, serverContentVersion: v1) == .upload)
        #expect(EditConflict.decide(baseContentVersion: v1, baseIsBeforeFirstSync: false, serverContentVersion: v2) == .keepBoth)
    }

    // MARK: - ConflictCopyName

    @Test func conflictCopyNamesFormatExpectedStemsAndExtensions() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 21, hour: 7, minute: 58
        )))

        #expect(ConflictCopyName.make(for: "notes.txt", date: date, timeZone: utc)
                == "notes (conflicted copy 2026-11-21 0758).txt")
        #expect(ConflictCopyName.make(for: "archive.tar.gz", date: date, timeZone: utc)
                == "archive.tar (conflicted copy 2026-11-21 0758).gz")
        #expect(ConflictCopyName.make(for: "Makefile", date: date, timeZone: utc)
                == "Makefile (conflicted copy 2026-11-21 0758)")
        #expect(ConflictCopyName.make(for: ".bashrc", date: date, timeZone: utc)
                == ".bashrc (conflicted copy 2026-11-21 0758)")
        #expect(ConflictCopyName.make(for: ".env.local", date: date, timeZone: utc)
                == ".env.local (conflicted copy 2026-11-21 0758)")
        #expect(ConflictCopyName.make(for: "notes.", date: date, timeZone: utc)
                == "notes. (conflicted copy 2026-11-21 0758)")
        #expect(ConflictCopyName.make(for: "Release 1.2 Notes", date: date, timeZone: utc)
                == "Release 1.2 Notes (conflicted copy 2026-11-21 0758)")
        #expect(ConflictCopyName.make(for: "Café notes 2026.pdf", date: date, timeZone: utc)
                == "Café notes 2026 (conflicted copy 2026-11-21 0758).pdf")
        #expect(ConflictCopyName.make(for: "notes.txt", date: date, timeZone: utc, number: 2)
                == "notes (conflicted copy 2026-11-21 0758 2).txt")
    }

    // MARK: - DestinationCheck

    @Test func caseOnlyRenameRequiresExactSameParent() {
        #expect(DestinationCheck.isCaseOnlyRename(from: "a/x.txt", to: "a/X.txt"))
        #expect(DestinationCheck.isCaseOnlyRename(from: "x.txt", to: "X.txt"))
        #expect(!DestinationCheck.isCaseOnlyRename(from: "a/x.txt", to: "a/x.txt"))
        #expect(!DestinationCheck.isCaseOnlyRename(from: "a/x.txt", to: "a/y.txt"))
        #expect(!DestinationCheck.isCaseOnlyRename(from: "A/x.txt", to: "a/x.txt"))
    }

    // MARK: - CollisionName

    @Test func collisionNamesForFilesAndFolders() {
        #expect(CollisionName.firstNumber(for: "report.pdf", isFolder: false) == 2)
        #expect(CollisionName.candidate(for: "report.pdf", number: 2, isFolder: false) == "report 2.pdf")

        // The first candidate for "report 2.pdf" starts at firstNumber (3) -> "report 3.pdf".
        #expect(CollisionName.firstNumber(for: "report 2.pdf", isFolder: false) == 3)
        #expect(CollisionName.candidate(for: "report 2.pdf", number: 3, isFolder: false) == "report 3.pdf")
        #expect(CollisionName.candidate(for: "report 2.pdf", number: 2, isFolder: false) == "report 2.pdf")

        #expect(CollisionName.firstNumber(for: "report 20.pdf", isFolder: false) == 21)
        #expect(CollisionName.candidate(for: "report 20.pdf", number: 21, isFolder: false) == "report 21.pdf")

        #expect(CollisionName.candidate(for: "archive.tar.gz", number: 2, isFolder: false) == "archive.tar 2.gz")
        #expect(CollisionName.candidate(for: "Makefile", number: 2, isFolder: false) == "Makefile 2")
        #expect(CollisionName.candidate(for: ".bashrc", number: 2, isFolder: false) == ".bashrc 2")
        #expect(CollisionName.firstNumber(for: ".env.local", isFolder: false) == 2)
        #expect(CollisionName.candidate(for: ".env.local", number: 2, isFolder: false) == ".env.local 2")
        #expect(CollisionName.firstNumber(for: "notes.", isFolder: false) == 2)
        #expect(CollisionName.candidate(for: "notes.", number: 2, isFolder: false) == "notes. 2")
        #expect(CollisionName.firstNumber(for: "Release 1.2 Notes", isFolder: false) == 2)
        #expect(CollisionName.candidate(for: "Release 1.2 Notes", number: 2, isFolder: false) == "Release 1.2 Notes 2")
        #expect(CollisionName.firstNumber(for: "Release 1.2 Notes 2", isFolder: false) == 3)
        #expect(CollisionName.candidate(for: "Release 1.2 Notes 2", number: 3, isFolder: false) == "Release 1.2 Notes 3")

        // Folders always append at the end, even when the name contains a dot.
        #expect(CollisionName.candidate(for: "v1.2", number: 2, isFolder: true) == "v1.2 2")
        #expect(CollisionName.firstNumber(for: "Photos 4", isFolder: true) == 5)
        #expect(CollisionName.candidate(for: "Photos 4", number: 5, isFolder: true) == "Photos 5")
    }

    @Test func nonCounterTrailingNumbersAreKeptIntact() {
        // All digits with no space: not a counter.
        #expect(CollisionName.firstNumber(for: "2026", isFolder: true) == 2)
        #expect(CollisionName.candidate(for: "2026", number: 2, isFolder: true) == "2026 2")

        // Leading zero, zero counter, empty stem before space, > 1_000_000, overflowing Int, or non-ASCII digits: not counters.
        let hugeDigits = String(repeating: "9", count: 30)
        for name in [
            "Track 01.mp3",
            "2026-11-21 0758.txt",
            " 2.pdf",
            "x 0.txt",
            "report 1000001.pdf",
            "report \(Int.max - 5).pdf",
            "report \(Int.max).pdf",
            "report \(hugeDigits).pdf",
            "report ٢.pdf",
        ] {
            #expect(CollisionName.firstNumber(for: name, isFolder: false) == 2)
        }
        #expect(CollisionName.candidate(for: "Track 01.mp3", number: 2, isFolder: false) == "Track 01 2.mp3")
        #expect(CollisionName.candidate(for: "2026-11-21 0758.txt", number: 2, isFolder: false) == "2026-11-21 0758 2.txt")
        #expect(CollisionName.candidate(for: " 2.pdf", number: 2, isFolder: false) == " 2 2.pdf")
        #expect(CollisionName.candidate(for: "x 0.txt", number: 2, isFolder: false) == "x 0 2.txt")
        #expect(CollisionName.candidate(for: "report 1000001.pdf", number: 2, isFolder: false) == "report 1000001 2.pdf")
        #expect(CollisionName.candidate(for: "report \(Int.max - 5).pdf", number: 2, isFolder: false) == "report \(Int.max - 5) 2.pdf")
        #expect(CollisionName.candidate(for: "report \(Int.max).pdf", number: 2, isFolder: false) == "report \(Int.max) 2.pdf")
        #expect(CollisionName.candidate(for: "report \(hugeDigits).pdf", number: 2, isFolder: false) == "report \(hugeDigits) 2.pdf")
        #expect(CollisionName.candidate(for: "report ٢.pdf", number: 2, isFolder: false) == "report ٢ 2.pdf")
    }

    @Test func longNamesAreShortenedToAtMost255UTF8BytesOnCharacterBoundaries() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 21, hour: 7, minute: 58
        )))

        let asciiBase = String(repeating: "a", count: 250)
        let asciiFile = "\(asciiBase).txt"
        let asciiCollision = CollisionName.candidate(for: asciiFile, number: 2, isFolder: false)
        #expect(asciiCollision.utf8.count == 255)
        #expect(asciiCollision.hasSuffix(" 2.txt"))
        #expect(asciiCollision.dropLast(6) == Substring(String(repeating: "a", count: 249)))

        let asciiConflict = ConflictCopyName.make(for: asciiFile, date: date, timeZone: utc, number: 2)
        #expect(asciiConflict.utf8.count == 255)
        #expect(asciiConflict.hasSuffix(" (conflicted copy 2026-11-21 0758 2).txt"))

        // Multi-byte characters ("é" = 2 UTF-8 bytes, "📦" = 4 UTF-8 bytes) must not split mid-character.
        let eAcuteFile = String(repeating: "é", count: 126) + ".txt" // 252 + 4 = 256 bytes
        let eAcuteCollision = CollisionName.candidate(for: eAcuteFile, number: 2, isFolder: false)
        #expect(eAcuteCollision.utf8.count <= 255)
        #expect(eAcuteCollision.utf8.count == 254) // 124 * 2 + 6
        #expect(eAcuteCollision.hasSuffix(" 2.txt"))

        let emojiFile = String(repeating: "📦", count: 63) + ".txt" // 252 + 4 = 256 bytes
        let emojiConflict = ConflictCopyName.make(for: emojiFile, date: date, timeZone: utc)
        #expect(emojiConflict.utf8.count <= 255)
        #expect(emojiConflict.hasSuffix(" (conflicted copy 2026-11-21 0758).txt"))

        // When even an empty base cannot fit (very long extension), leave the name unchanged.
        let hugeExt = "." + String(repeating: "x", count: 255)
        let hugeExtFile = "stem\(hugeExt)"
        #expect(CollisionName.candidate(for: hugeExtFile, number: 2, isFolder: false) == "stem 2\(hugeExt)")
        #expect(ConflictCopyName.make(for: hugeExtFile, date: date, timeZone: utc)
                == "stem (conflicted copy 2026-11-21 0758)\(hugeExt)")
    }
}
