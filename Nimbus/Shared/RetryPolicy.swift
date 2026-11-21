import Foundation
import RcloneKit
import os

/// Which failures of an rclone call are worth another attempt.
///
/// Every call from the File Provider extension can race the daemon's startup
/// or a port/credential rotation, so failures where rclone never ran the call
/// (`notSent`) or where the outcome is unknown (`ambiguous`) are retried for
/// both reads and writes (writes are written to be safe to re-run). A 5xx
/// (`serverError`) is retried only for reads: rclone already performs its own
/// low-level retries, so a failed write job is a real failure and re-running
/// it would repeat the whole upload or move. Permanent errors (404, 400,
/// `.noSuchItem`, decoding failures) and cancellations stop immediately.
enum RetryPolicy {
    enum ErrorClass: Equatable, Sendable {
        case notSent
        case ambiguous
        case serverError
        case permanent
        case cancelled
    }

    enum Kind: Sendable {
        case read
        case write
    }

    static func classify(_ error: Error) -> ErrorClass {
        if error is CancellationError {
            return .cancelled
        }
        if error is RcloneJobLostError {
            return .ambiguous
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return .cancelled
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
                return .notSent
            case .timedOut, .networkConnectionLost, .badServerResponse, .cannotParseResponse, .zeroByteResource:
                return .ambiguous
            default:
                return .permanent
            }
        }
        if let rcloneError = error as? RcloneError {
            switch rcloneError {
            case .serverNotRunning:
                return .notSent
            case .requestFailed(status: 401, _):
                return .notSent
            case .requestFailed(let status, _) where (500...599).contains(status):
                return .serverError
            case .requestFailed:
                return .permanent
            case .invalidResponse:
                return .ambiguous
            case .decodingError:
                return .permanent
            }
        }
        // Everything else, including `NSFileProviderError(.noSuchItem)` from an
        // item lookup and local file errors, won't change on a retry.
        return .permanent
    }

    static func shouldRetry(_ error: Error, kind: Kind) -> Bool {
        switch classify(error) {
        case .notSent, .ambiguous:
            true
        case .serverError:
            kind == .read
        case .permanent, .cancelled:
            false
        }
    }

    /// The retry loop, free of the extension's side effects so it can be tested.
    /// `body` gets the 0-based attempt number. `beforeRetry(attempt)` runs before
    /// attempts 1…; `sleep` waits the backoff (attempt seconds).
    static func run<T: Sendable>(
        kind: Kind,
        maxAttempts: Int,
        operation: String,
        logger: Logger,
        beforeRetry: @Sendable (Int) async -> Void,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        _ body: @Sendable (Int) async throws -> T
    ) async throws -> T {
        let limit = max(1, maxAttempts)
        for attempt in 0..<limit {
            try Task.checkCancellation()
            if attempt > 0 {
                await beforeRetry(attempt)
                try await sleep(.seconds(attempt))
            }
            do {
                return try await body(attempt)
            } catch {
                let errorClass = classify(error)
                logger.warning("\(operation) attempt \(attempt + 1)/\(limit) failed (\(String(describing: errorClass))): \(String(describing: error))")
                guard shouldRetry(error, kind: kind) else {
                    throw error
                }
                if attempt + 1 >= limit {
                    logger.error("\(operation) gave up after \(limit) attempts")
                    throw error
                }
            }
        }
        preconditionFailure("unreachable")
    }
}
