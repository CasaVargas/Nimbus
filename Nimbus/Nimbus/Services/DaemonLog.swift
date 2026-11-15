import Foundation

/// Keeps what rclone prints (notices, warnings, errors) in a file. It used
/// to go to /dev/null, which hid the one line that explained why Google
/// Drive folders timed out. Capped: when the file passes `limit` the older
/// half is dropped.
final class DaemonLog: @unchecked Sendable {
    static let defaultLimit = 1_000_000

    let url: URL
    private let limit: Int
    private let queue = DispatchQueue(label: "app.casavargas.nimbus.daemon-log")

    init(url: URL, limit: Int = DaemonLog.defaultLimit) {
        self.url = url
        self.limit = limit
    }

    /// `~/Library/Logs/Nimbus/rclone.log`.
    static func standard() -> DaemonLog? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first.map {
            DaemonLog(url: $0.appendingPathComponent("Logs/Nimbus/rclone.log"))
        }
    }

    /// A pipe to give the process as stderr; everything written to it is
    /// appended to the file until the process closes it.
    func makePipe() -> Pipe {
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil // end of file: the process exited
                return
            }
            self?.append(data)
        }
        return pipe
    }

    func append(_ data: Data) {
        queue.async { [url, limit] in
            let manager = FileManager.default
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var contents = (try? Data(contentsOf: url)) ?? Data()
            contents.append(data)
            if contents.count > limit {
                // Keep the newer half, starting on a line boundary.
                let tail = contents.suffix(limit / 2)
                let start = tail.firstIndex(of: UInt8(ascii: "\n")).map { tail.index(after: $0) } ?? tail.startIndex
                contents = Data(tail[start...])
            }
            try? contents.write(to: url, options: .atomic)
        }
    }

    /// Waits for pending writes. For tests.
    func flush() {
        queue.sync {}
    }
}
