import Foundation

struct ParsedRemote: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let type: String
    let parameters: [String: String]
}

enum RcloneConfParser {
    static func parse(_ content: String) -> [ParsedRemote] {
        var remotes: [ParsedRemote] = []
        var currentName: String?
        var currentParams: [String: String] = [:]

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                if let name = currentName {
                    let type = currentParams.removeValue(forKey: "type") ?? "unknown"
                    remotes.append(ParsedRemote(name: name, type: type, parameters: currentParams))
                }
                currentName = String(line.dropFirst().dropLast())
                currentParams = [:]
                continue
            }

            if currentName != nil, let eqIndex = line.firstIndex(of: "=") {
                let key = line[line.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
                currentParams[key] = value
            }
        }

        if let name = currentName {
            let type = currentParams.removeValue(forKey: "type") ?? "unknown"
            remotes.append(ParsedRemote(name: name, type: type, parameters: currentParams))
        }

        return remotes
    }
}
