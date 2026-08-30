import Foundation

public final class RcloneClient: @unchecked Sendable {
    public private(set) var port: Int
    private let session: URLSession

    public init(port: Int = 5572, session: URLSession? = nil) {
        self.port = port
        self.session = session ?? {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            // 900, not 300: an OAuth config/create blocks while rclone waits
            // on the browser callback, and timeoutIntervalForResource is the
            // hard ceiling for the whole transfer regardless of any
            // per-request timeoutInterval.
            config.timeoutIntervalForResource = 900
            return URLSession(configuration: config)
        }()
    }

    public func updatePort(_ newPort: Int) {
        port = newPort
    }

    private var baseURL: String {
        "http://127.0.0.1:\(port)"
    }

    public func call<T: Decodable & Sendable>(
        _ endpoint: String,
        params: [String: any Sendable] = [:]
    ) async throws -> T {
        let url = URL(string: "\(baseURL)/\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !params.isEmpty {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } else {
            request.httpBody = "{}".data(using: .utf8)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RcloneError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(RcloneErrorResponse.self, from: data) {
                throw RcloneError.requestFailed(
                    status: errorResponse.status,
                    message: errorResponse.error
                )
            }
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw RcloneError.requestFailed(
                status: httpResponse.statusCode,
                message: body
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RcloneError.decodingError(error.localizedDescription)
        }
    }

    public func call(
        _ endpoint: String,
        params: [String: any Sendable] = [:]
    ) async throws {
        let _: EmptyResponse = try await call(endpoint, params: params)
    }

    /// Downloads raw file bytes via the rclone RC API and writes them to
    /// a local destination URL. Uses `operations/cat` which streams the
    /// file content as the HTTP response body — no local filesystem access
    /// by rclone is needed, making this safe for sandboxed callers.
    /// Characters safe to leave literal in the `/[fs]/path` download URL.
    /// Everything else (spaces, brackets, colons, unicode, "•", …) gets
    /// percent-encoded; rclone decodes the path server-side.
    private static let downloadPathAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~/")
        return set
    }()

    public func downloadFile(fs: String, remote: String, to destination: URL) async throws {
        // rclone's RC API has NO download method — operations/cat does not
        // exist (404 "couldn't find method"). File content is served over
        // plain HTTP when rcd runs with --rc-serve (RcloneDaemon passes it):
        //   GET /[<fs>]/<path from fs root>
        // Verified live against rclone rcd: GET /%5Bgdrive:%5D/file.pdf → 200.
        let encFs = fs.addingPercentEncoding(withAllowedCharacters: Self.downloadPathAllowed) ?? fs
        let encRemote = remote.addingPercentEncoding(withAllowedCharacters: Self.downloadPathAllowed) ?? remote
        guard let url = URL(string: "\(baseURL)/%5B\(encFs)%5D/\(encRemote)") else {
            throw RcloneError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 600

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RcloneError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw RcloneError.requestFailed(status: httpResponse.statusCode, message: body)
        }

        try data.write(to: destination, options: .atomic)
    }

    /// Uploads a local file to a remote via rclone's `operations/uploadfile`
    /// endpoint using multipart form data. Safe from sandboxed callers since
    /// the extension reads the file and sends bytes over HTTP.
    ///
    /// `remote` is the destination *directory*; the uploaded object's name
    /// comes from the multipart part's `filename`, not necessarily from
    /// `localURL`. Pass `filename` explicitly when the on-disk staging file's
    /// name (e.g. a File Provider system temp name) doesn't match the
    /// desired remote name — otherwise it defaults to `localURL`'s last path
    /// component.
    public func uploadFile(from localURL: URL, fs: String, remote: String, filename: String? = nil) async throws {
        // rclone reads `fs`/`remote` from the URL query ONLY — multipart
        // form fields for them come back 400 "Didn't find key \"remote\""
        // (verified against rclone rcd). The body carries just the file part.
        var components = URLComponents(string: "\(baseURL)/operations/uploadfile")!
        components.queryItems = [
            URLQueryItem(name: "fs", value: fs),
            URLQueryItem(name: "remote", value: remote),
        ]
        guard let url = components.url else { throw RcloneError.invalidResponse }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        let fileData = try Data(contentsOf: localURL)
        let uploadFilename = filename ?? localURL.lastPathComponent

        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(uploadFilename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RcloneError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw RcloneError.requestFailed(status: httpResponse.statusCode, message: responseBody)
        }
    }

    public func healthCheck() async -> Bool {
        do {
            let _: EmptyResponse = try await call("rc/noop")
            return true
        } catch {
            return false
        }
    }
}

private struct EmptyResponse: Decodable {}
