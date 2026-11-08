import Foundation

/// One side of a copy, sync or backup: a folder on this Mac, or a folder in
/// a cloud (path "" is the cloud's root). `fs` is what rclone takes.
enum TransferEndpoint: Hashable, Sendable {
    case local(path: String)
    case cloud(remote: String, path: String)

    /// rclone's fs string: `"/Users/x/Docs"`, `"b2:"` or `"b2:mac/Docs"`.
    var fs: String {
        switch self {
        case .local(let path): path
        case .cloud(let remote, let path): "\(remote):\(path)"
        }
    }

    /// The last folder name, or the cloud's name at its root.
    var displayName: String {
        switch self {
        case .local(let path):
            let name = (path as NSString).lastPathComponent
            return name.isEmpty ? path : name
        case .cloud(let remote, let path):
            let trimmed = Self.trimmed(path)
            return trimmed.isEmpty ? remote : (trimmed as NSString).lastPathComponent
        }
    }

    /// The cloud this endpoint lives in; nil for a folder on this Mac.
    var cloudName: String? {
        if case .cloud(let remote, _) = self { return remote }
        return nil
    }

    func appending(_ component: String) -> TransferEndpoint {
        let child = Self.trimmed(component)
        switch self {
        case .local(let path):
            var base = path
            while base.count > 1, base.hasSuffix("/") { base.removeLast() }
            guard !child.isEmpty else { return .local(path: base) }
            return .local(path: base == "/" ? "/\(child)" : "\(base)/\(child)")
        case .cloud(let remote, let path):
            let base = Self.trimmed(path)
            guard !child.isEmpty else { return .cloud(remote: remote, path: base) }
            return .cloud(remote: remote, path: base.isEmpty ? child : "\(base)/\(child)")
        }
    }

    /// True when `other` is this folder or inside it, on the same side.
    func contains(_ other: TransferEndpoint) -> Bool {
        switch (self, other) {
        case (.local(let mine), .local(let theirs)):
            return Self.isPath(Self.trimmed(theirs), inside: Self.trimmed(mine))
        case (.cloud(let myRemote, let mine), .cloud(let theirRemote, let theirs)):
            guard myRemote == theirRemote else { return false }
            return Self.isPath(Self.trimmed(theirs), inside: Self.trimmed(mine))
        default:
            return false
        }
    }

    private static func isPath(_ path: String, inside parent: String) -> Bool {
        parent.isEmpty || path == parent || path.hasPrefix(parent + "/")
    }

    private static func trimmed(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

extension TransferEndpoint: Codable {
    private enum CodingKeys: String, CodingKey { case kind, path, remote }
    private enum Kind: String, Codable { case local, cloud }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(String.self, forKey: .path)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .local: self = .local(path: path)
        case .cloud: self = .cloud(remote: try container.decode(String.self, forKey: .remote), path: path)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .local(let path):
            try container.encode(Kind.local, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .cloud(let remote, let path):
            try container.encode(Kind.cloud, forKey: .kind)
            try container.encode(remote, forKey: .remote)
            try container.encode(path, forKey: .path)
        }
    }
}
