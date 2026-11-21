import FileProvider
import Foundation
import RcloneKit
import Testing
import os

@testable import Nimbus

private final class RetryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedAttempts: [Int] = []
    private var storedBeforeRetries: [Int] = []
    private var storedSleeps: [Duration] = []

    var attempts: [Int] { lock.withLock { storedAttempts } }
    var beforeRetries: [Int] { lock.withLock { storedBeforeRetries } }
    var sleeps: [Duration] { lock.withLock { storedSleeps } }

    func recordAttempt(_ attempt: Int) -> Int {
        lock.withLock {
            storedAttempts.append(attempt)
            return storedAttempts.count
        }
    }

    func recordBeforeRetry(_ attempt: Int) {
        lock.withLock { storedBeforeRetries.append(attempt) }
    }

    func recordSleep(_ duration: Duration) {
        lock.withLock { storedSleeps.append(duration) }
    }
}

private struct UnlistedError: Error, Equatable {}

@Suite("RetryPolicy")
struct RetryPolicyTests {
    private let logger = Logger(subsystem: "app.casavargas.nimbus.tests", category: "retry")

    @Test func classifiesNotSentErrors() {
        let errors: [any Error] = [
            URLError(.cannotConnectToHost),
            URLError(.cannotFindHost),
            URLError(.dnsLookupFailed),
            URLError(.notConnectedToInternet),
            RcloneError.serverNotRunning,
            RcloneError.requestFailed(status: 401, message: "unauthorized"),
        ]
        for error in errors {
            #expect(RetryPolicy.classify(error) == .notSent)
        }
    }

    @Test func classifiesAmbiguousErrors() {
        let errors: [any Error] = [
            URLError(.timedOut),
            URLError(.networkConnectionLost),
            URLError(.badServerResponse),
            URLError(.cannotParseResponse),
            URLError(.zeroByteResource),
            RcloneError.invalidResponse,
            RcloneJobLostError(jobID: 9),
        ]
        for error in errors {
            #expect(RetryPolicy.classify(error) == .ambiguous)
        }
    }

    @Test func classifiesServerErrors() {
        for status in [500, 502, 503, 599] {
            let error = RcloneError.requestFailed(status: status, message: "boom")
            #expect(RetryPolicy.classify(error) == .serverError)
        }
    }

    @Test func classifiesPermanentErrors() {
        let errors: [any Error] = [
            RcloneError.requestFailed(status: 400, message: "bad request"),
            RcloneError.requestFailed(status: 403, message: "forbidden"),
            RcloneError.requestFailed(status: 404, message: "not found"),
            RcloneError.decodingError("missing key"),
            NSFileProviderError(.noSuchItem),
            CocoaError(.fileNoSuchFile),
            URLError(.badURL),
            UnlistedError(),
        ]
        for error in errors {
            #expect(RetryPolicy.classify(error) == .permanent)
        }
    }

    @Test func classifiesCancelledErrors() {
        #expect(RetryPolicy.classify(CancellationError()) == .cancelled)
        #expect(RetryPolicy.classify(URLError(.cancelled)) == .cancelled)
    }

    @Test func shouldRetryFollowsReadAndWriteRules() {
        let notSent = URLError(.cannotConnectToHost)
        #expect(RetryPolicy.shouldRetry(notSent, kind: .read))
        #expect(RetryPolicy.shouldRetry(notSent, kind: .write))

        let ambiguous = RcloneJobLostError(jobID: 1)
        #expect(RetryPolicy.shouldRetry(ambiguous, kind: .read))
        #expect(RetryPolicy.shouldRetry(ambiguous, kind: .write))

        let serverError = RcloneError.requestFailed(status: 500, message: "quota exceeded")
        #expect(RetryPolicy.shouldRetry(serverError, kind: .read))
        #expect(!RetryPolicy.shouldRetry(serverError, kind: .write))

        let permanent = RcloneError.requestFailed(status: 404, message: "not found")
        #expect(!RetryPolicy.shouldRetry(permanent, kind: .read))
        #expect(!RetryPolicy.shouldRetry(permanent, kind: .write))

        let cancelled = CancellationError()
        #expect(!RetryPolicy.shouldRetry(cancelled, kind: .read))
        #expect(!RetryPolicy.shouldRetry(cancelled, kind: .write))
    }

    @Test func requestFailed404RunsOnceAndRethrows() async {
        let recorder = RetryRecorder()
        do {
            try await RetryPolicy.run(
                kind: .read,
                maxAttempts: 5,
                operation: "test.404",
                logger: logger,
                beforeRetry: { recorder.recordBeforeRetry($0) },
                sleep: { recorder.recordSleep($0) }
            ) { attempt in
                _ = recorder.recordAttempt(attempt)
                throw RcloneError.requestFailed(status: 404, message: "not found")
            }
            Issue.record("Expected 404 to be rethrown")
        } catch RcloneError.requestFailed(let status, let message) {
            #expect(status == 404)
            #expect(message == "not found")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(recorder.attempts == [0])
        #expect(recorder.beforeRetries.isEmpty)
        #expect(recorder.sleeps.isEmpty)
    }

    @Test func fileProviderNoSuchItemRunsOnceAndRethrows() async {
        let recorder = RetryRecorder()
        do {
            try await RetryPolicy.run(
                kind: .read,
                maxAttempts: 5,
                operation: "test.noSuchItem",
                logger: logger,
                beforeRetry: { recorder.recordBeforeRetry($0) },
                sleep: { recorder.recordSleep($0) }
            ) { attempt in
                _ = recorder.recordAttempt(attempt)
                throw NSFileProviderError(.noSuchItem)
            }
            Issue.record("Expected .noSuchItem to be rethrown")
        } catch let error as NSFileProviderError {
            #expect(error.code == .noSuchItem)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(recorder.attempts == [0])
        #expect(recorder.beforeRetries.isEmpty)
        #expect(recorder.sleeps.isEmpty)
    }

    @Test func cannotConnectToHostRunsMaxAttemptsAndRethrowsLastError() async {
        let recorder = RetryRecorder()
        do {
            try await RetryPolicy.run(
                kind: .write,
                maxAttempts: 5,
                operation: "test.connect",
                logger: logger,
                beforeRetry: { recorder.recordBeforeRetry($0) },
                sleep: { recorder.recordSleep($0) }
            ) { attempt in
                _ = recorder.recordAttempt(attempt)
                throw URLError(.cannotConnectToHost, userInfo: ["attempt": attempt])
            }
            Issue.record("Expected URLError to be rethrown")
        } catch let error as URLError {
            #expect(error.code == .cannotConnectToHost)
            #expect(error.userInfo["attempt"] as? Int == 4)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(recorder.attempts == [0, 1, 2, 3, 4])
        #expect(recorder.beforeRetries == [1, 2, 3, 4])
        #expect(recorder.sleeps == [.seconds(1), .seconds(2), .seconds(3), .seconds(4)])
    }

    @Test func writeWith500RunsOnceWhileReadWith500RunsMaxAttempts() async {
        let writeRecorder = RetryRecorder()
        do {
            try await RetryPolicy.run(
                kind: .write,
                maxAttempts: 5,
                operation: "test.write500",
                logger: logger,
                beforeRetry: { writeRecorder.recordBeforeRetry($0) },
                sleep: { writeRecorder.recordSleep($0) }
            ) { attempt in
                _ = writeRecorder.recordAttempt(attempt)
                throw RcloneError.requestFailed(status: 500, message: "quota exceeded")
            }
            Issue.record("Expected 500 to be rethrown")
        } catch RcloneError.requestFailed(let status, _) {
            #expect(status == 500)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(writeRecorder.attempts == [0])
        #expect(writeRecorder.beforeRetries.isEmpty)
        #expect(writeRecorder.sleeps.isEmpty)

        let readRecorder = RetryRecorder()
        do {
            try await RetryPolicy.run(
                kind: .read,
                maxAttempts: 5,
                operation: "test.read500",
                logger: logger,
                beforeRetry: { readRecorder.recordBeforeRetry($0) },
                sleep: { readRecorder.recordSleep($0) }
            ) { attempt in
                _ = readRecorder.recordAttempt(attempt)
                throw RcloneError.requestFailed(status: 500, message: "try-\(attempt)")
            }
            Issue.record("Expected 500 to be rethrown")
        } catch RcloneError.requestFailed(let status, let message) {
            #expect(status == 500)
            #expect(message == "try-4")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(readRecorder.attempts == [0, 1, 2, 3, 4])
        #expect(readRecorder.beforeRetries == [1, 2, 3, 4])
        #expect(readRecorder.sleeps == [.seconds(1), .seconds(2), .seconds(3), .seconds(4)])
    }

    @Test func cancellationErrorStopsAtOnce() async {
        let recorder = RetryRecorder()
        await #expect(throws: CancellationError.self) {
            try await RetryPolicy.run(
                kind: .read,
                maxAttempts: 5,
                operation: "test.cancel",
                logger: logger,
                beforeRetry: { recorder.recordBeforeRetry($0) },
                sleep: { recorder.recordSleep($0) }
            ) { attempt in
                _ = recorder.recordAttempt(attempt)
                throw CancellationError()
            }
        }
        #expect(recorder.attempts == [0])
        #expect(recorder.beforeRetries.isEmpty)
        #expect(recorder.sleeps.isEmpty)
    }

    @Test func successOnSecondAttemptReturnsValueAndPassesAttemptNumbers() async throws {
        let recorder = RetryRecorder()
        let result = try await RetryPolicy.run(
            kind: .write,
            maxAttempts: 5,
            operation: "test.recover",
            logger: logger,
            beforeRetry: { recorder.recordBeforeRetry($0) },
            sleep: { recorder.recordSleep($0) }
        ) { attempt in
            let count = recorder.recordAttempt(attempt)
            if count == 1 {
                throw RcloneJobLostError(jobID: 42)
            }
            return "done-on-\(attempt)"
        }
        #expect(result == "done-on-1")
        #expect(recorder.attempts == [0, 1])
        #expect(recorder.beforeRetries == [1])
        #expect(recorder.sleeps == [.seconds(1)])
    }
}
