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
