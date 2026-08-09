import Foundation

public final class RcloneClient: @unchecked Sendable {
    public private(set) var port: Int
    private let session: URLSession

    public init(port: Int = 5572, session: URLSession? = nil) {
        self.port = port
        self.session = session ?? {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 300
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
    public func downloadFile(fs: String, remote: String, to destination: URL) async throws {
        let url = URL(string: "\(baseURL)/operations/cat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        let params: [String: Any] = ["fs": fs, "remote": remote]
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

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
