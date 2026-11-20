import Foundation
import Testing
@testable import RcloneKit

/// The parser before formatters were cached: a new formatter per call,
/// fractional seconds first. `FileItem.parseModTime` must return exactly
/// the same dates, since the File Provider extension builds item versions
/// from their bytes.
private func referenceParse(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}

private let modTimeSamples = [
    "2026-03-31T10:00:00Z",
    "2026-03-31T10:00:00.000000000Z",
    "2010-10-03T14:22:11.123456789Z",
    "2010-10-03T14:22:11.1239Z",
    "2010-10-03T14:22:11.9999Z",
    "2010-10-03T14:22:11.0005Z",
    "2010-10-03T14:22:11.1Z",
    "2025-12-17T00:17:02.729Z",
    "1960-10-03T14:22:11.1239Z",
    "0001-01-01T00:00:00Z",
    "2010-10-03T14:22:11.5-07:00",
    "2010-10-03T14:22:11+02:00",
    "2010-10-03T14:22:11.123+0530",
    "2010-10-03T14:22:11z",
    "2010-10-03 14:22:11Z",
    "2010-10-03T14:22Z",
    "not a date",
    "",
]

@Test func parseModTimeMatchesTheReferenceBitForBit() {
    for sample in modTimeSamples {
        let expected = referenceParse(sample)
        let actual = FileItem.parseModTime(sample)
        #expect(actual?.timeIntervalSinceReferenceDate.bitPattern == expected?.timeIntervalSinceReferenceDate.bitPattern,
                "\(sample)")
    }
}

@Test func parseModTimeMatchesTheReferenceForRandomTimestamps() {
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<2_000 {
        let seconds = Int64.random(in: -2_000_000_000...4_000_000_000, using: &generator)
        let base = Date(timeIntervalSince1970: TimeInterval(seconds))
        var text = ISO8601DateFormatter().string(from: base)
        let digits = Int.random(in: 0...9, using: &generator)
        if digits > 0 {
            let fraction = (0..<digits).map { _ in String(Int.random(in: 0...9, using: &generator)) }.joined()
            text = text.replacingOccurrences(of: "Z", with: ".\(fraction)Z")
        }
        let expected = referenceParse(text)
        #expect(FileItem.parseModTime(text)?.timeIntervalSinceReferenceDate.bitPattern
                == expected?.timeIntervalSinceReferenceDate.bitPattern, "\(text)")
    }
}

@Test func parseModTimeIsSafeFromManyThreads() async {
    let expected = modTimeSamples.map { referenceParse($0) }
    await withTaskGroup(of: Bool.self) { group in
        for _ in 0..<8 {
            group.addTask {
                (0..<200).allSatisfy { _ in
                    zip(modTimeSamples, expected).allSatisfy { FileItem.parseModTime($0) == $1 }
                }
            }
        }
        for await ok in group { #expect(ok) }
    }
}
