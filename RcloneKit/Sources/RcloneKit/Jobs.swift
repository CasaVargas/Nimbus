import Foundation

extension RcloneClient {
    public func listJobs() async throws -> [Int] {
        let response: JobListResponse = try await call("job/list")
        return response.jobids
    }

    public func jobStatus(id: Int) async throws -> Job {
        try await call("job/status", params: ["jobid": id])
    }

    public func stopJob(id: Int) async throws {
        try await call("job/stop", params: ["jobid": id])
    }
}
