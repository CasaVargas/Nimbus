import Foundation

/// The bytes of a File Provider item's version, shared by `FileProviderItem`
/// and the extension's edit-conflict check so both compute the same value.
enum ItemVersionBytes {
    /// The modtime's seconds as raw `Double` bytes; `[0]` when unknown.
    static func seconds(_ seconds: TimeInterval?) -> Data {
        if let seconds {
            withUnsafeBytes(of: seconds) { Data($0) }
        } else {
            Data([0])
        }
    }

    /// `seconds(_:)` plus, for files, `ItemSize.contentVersionSuffix(listed: size)`.
    static func content(seconds: TimeInterval?, size: Int64, isDir: Bool) -> Data {
        var data = Self.seconds(seconds)
        if !isDir {
            data.append(contentsOf: ItemSize.contentVersionSuffix(listed: size))
        }
        return data
    }
}

enum EditConflict {
    enum Decision: Equatable, Sendable {
        case upload
        case keepBoth
        case uploadUnlessDifferent
    }

    /// `serverContentVersion` is nil when no file exists on the server.
    static func decide(
        baseContentVersion: Data,
        baseIsBeforeFirstSync: Bool,
        serverContentVersion: Data?
    ) -> Decision {
        guard let serverContentVersion else { return .uploadUnlessDifferent }
        if baseIsBeforeFirstSync { return .uploadUnlessDifferent }
        return baseContentVersion == serverContentVersion ? .upload : .keepBoth
    }
}

enum ConflictCopyName {
    /// Builds a conflict-copy filename (e.g. `notes (conflicted copy 2026-11-21 0758).txt`).
    /// `number` 1 omits the counter; 2... appends `" 2"` before the closing parenthesis.
    static func make(for filename: String, date: Date, timeZone: TimeZone = .current, number: Int = 1) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let stamp = formatter.string(from: date)
        let suffix = number <= 1
            ? " (conflicted copy \(stamp))"
            : " (conflicted copy \(stamp) \(number))"

        // Dotfiles and names without an extension take the suffix at the end;
        // otherwise insert it before the last path extension.
        let (base, ext) = splitFilename(filename)
        return joinFilename(base: base, suffix: suffix, ext: ext)
    }
}

enum CollisionName {
    private static let maxCounter = 1_000_000

    /// Finder-style alternative for `filename` (`report.pdf` → `report 2.pdf`,
    /// `report 2.pdf` → `report 3.pdf`, folder `v1.2` → `v1.2 2`). `number` >= 2.
    ///
    /// When `filename` already ends in a counter (`report 2.pdf`), start at
    /// `firstNumber(for:isFolder:)` (`3`) so the first candidate is `report 3.pdf`.
    static func candidate(for filename: String, number: Int, isFolder: Bool) -> String {
        let (base, ext) = splitFilename(filename, isFolder: isFolder)
        let (stem, _) = splitCounter(base)
        return joinFilename(base: stem, suffix: " \(number)", ext: ext)
    }

    /// The number to start from: 2, or one above a trailing `" <n>"` already in the base.
    static func firstNumber(for filename: String, isFolder: Bool) -> Int {
        let (base, _) = splitFilename(filename, isFolder: isFolder)
        if let existing = splitCounter(base).number {
            return max(2, existing + 1)
        }
        return 2
    }

    private static func splitCounter(_ base: Substring) -> (stem: Substring, number: Int?) {
        guard let space = base.lastIndex(of: " "), space > base.startIndex else {
            return (base, nil)
        }
        let digits = base[base.index(after: space)...]
        guard !digits.isEmpty,
              !digits.hasPrefix("0"),
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let n = Int(digits),
              n >= 1,
              n <= maxCounter else {
            return (base, nil)
        }
        return (base[..<space], n)
    }
}

private let maxFilenameUTF8Bytes = 255

/// Splits `filename` into `(base, ext)` where `ext` includes the leading `.`,
/// or `(filename, "")` for folders, dotfiles, and names without a space-free
/// extension.
private func splitFilename(_ filename: String, isFolder: Bool = false) -> (base: Substring, ext: Substring) {
    if !isFolder,
       !filename.hasPrefix("."),
       let dot = filename.lastIndex(of: "."),
       dot < filename.index(before: filename.endIndex),
       !filename[filename.index(after: dot)...].contains(" ") {
        return (filename[..<dot], filename[dot...])
    }
    return (filename[...], "")
}

/// Joins `base`, `suffix` and `ext`, shortening `base` on a `Character`
/// boundary so the result is at most 255 UTF-8 bytes. Leaves the name as it is
/// when even an empty base cannot fit.
private func joinFilename(base: Substring, suffix: String, ext: Substring) -> String {
    let tailBytes = suffix.utf8.count + ext.utf8.count
    guard base.utf8.count + tailBytes > maxFilenameUTF8Bytes else {
        return "\(base)\(suffix)\(ext)"
    }
    let budget = maxFilenameUTF8Bytes - tailBytes
    guard budget >= 0 else {
        return "\(base)\(suffix)\(ext)"
    }
    var used = 0
    var end = base.startIndex
    while end < base.endIndex {
        let next = base.index(after: end)
        let charBytes = base[end..<next].utf8.count
        if used + charBytes > budget { break }
        used += charBytes
        end = next
    }
    return "\(base[..<end])\(suffix)\(ext)"
}

enum DestinationCheck {
    /// Same parent path (exact) and filenames that differ only in case.
    static func isCaseOnlyRename(from source: String, to destination: String) -> Bool {
        let (srcParent, srcName) = split(source)
        let (dstParent, dstName) = split(destination)
        guard srcParent == dstParent, srcName != dstName else { return false }
        return srcName.caseInsensitiveCompare(dstName) == .orderedSame
    }

    private static func split(_ path: String) -> (parent: String, name: String) {
        guard let slash = path.lastIndex(of: "/") else { return ("", path) }
        return (String(path[..<slash]), String(path[path.index(after: slash)...]))
    }
}
