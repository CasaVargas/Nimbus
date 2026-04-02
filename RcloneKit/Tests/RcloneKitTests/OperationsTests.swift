import Foundation
import Testing
@testable import RcloneKit

@Test func listFiles() async throws {
    let client = makeTestClient()
    let files = try await client.listFiles(fs: "gdrive:", remote: "")
    #expect(files.count == 2)
    #expect(files[0].name == "photo.jpg")
    #expect(files[1].isDir == true)
}

@Test func mkdir() async throws {
    let client = makeTestClient()
    try await client.mkdir(fs: "gdrive:", remote: "new-folder")
}

@Test func deleteFile() async throws {
    let client = makeTestClient()
    try await client.deleteFile(fs: "gdrive:", remote: "old-file.txt")
}

@Test func about() async throws {
    let client = makeTestClient()
    let info = try await client.about(fs: "gdrive:")
    #expect(info.total == 1_000_000)
    #expect(info.used == 500_000)
}
