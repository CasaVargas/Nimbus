import Foundation

extension RcloneClient {
    public func copy(srcFs: String, dstFs: String) async throws -> Int {
        let response: AsyncJobResponse = try await call("sync/copy", params: [
            "srcFs": srcFs,
            "dstFs": dstFs,
            "_async": true,
        ])
        return response.jobid
    }

    public func sync(srcFs: String, dstFs: String) async throws -> Int {
        let response: AsyncJobResponse = try await call("sync/sync", params: [
            "srcFs": srcFs,
            "dstFs": dstFs,
            "_async": true,
        ])
        return response.jobid
    }
}
