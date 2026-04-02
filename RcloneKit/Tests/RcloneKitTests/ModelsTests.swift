import Foundation
import Testing
@testable import RcloneKit

@Test func decodesFileItem() throws {
    let json = """
    {
        "Path": "documents/report.pdf",
        "Name": "report.pdf",
        "Size": 1048576,
        "MimeType": "application/pdf",
        "ModTime": "2026-03-31T10:00:00.000000000Z",
        "IsDir": false,
        "ID": "abc123"
    }
    """.data(using: .utf8)!

    let item = try JSONDecoder().decode(FileItem.self, from: json)
    #expect(item.path == "documents/report.pdf")
    #expect(item.name == "report.pdf")
    #expect(item.size == 1_048_576)
    #expect(item.mimeType == "application/pdf")
    #expect(item.isDir == false)
    #expect(item.fileID == "abc123")
    #expect(item.modTime != nil)
}

@Test func decodesFileItemDirectory() throws {
    let json = """
    {
        "Path": "photos",
        "Name": "photos",
        "Size": -1,
        "MimeType": "inode/directory",
        "ModTime": "2026-03-31T10:00:00.000000000Z",
        "IsDir": true
    }
    """.data(using: .utf8)!

    let item = try JSONDecoder().decode(FileItem.self, from: json)
    #expect(item.isDir == true)
    #expect(item.fileID == nil)
}

@Test func decodesProvider() throws {
    let json = """
    {
        "Name": "s3",
        "Description": "Amazon S3",
        "Prefix": "s3",
        "Options": [
            {
                "Name": "access_key_id",
                "Help": "AWS Access Key ID",
                "Default": "",
                "Value": "",
                "Type": "string",
                "Required": true,
                "IsPassword": false,
                "Advanced": false
            },
            {
                "Name": "secret_access_key",
                "Help": "AWS Secret Access Key",
                "Default": "",
                "Value": "",
                "Type": "string",
                "Required": true,
                "IsPassword": true,
                "Advanced": false
            }
        ]
    }
    """.data(using: .utf8)!

    let provider = try JSONDecoder().decode(Provider.self, from: json)
    #expect(provider.name == "s3")
    #expect(provider.description == "Amazon S3")
    #expect(provider.options.count == 2)
    #expect(provider.options[0].required == true)
    #expect(provider.options[1].isPassword == true)
}

@Test func decodesJobStatus() throws {
    let json = """
    {
        "id": 42,
        "group": "job/42",
        "startTime": "2026-03-31T10:00:00Z",
        "endTime": "2026-03-31T10:05:00Z",
        "error": "",
        "finished": true,
        "success": true,
        "duration": 300.0,
        "output": {}
    }
    """.data(using: .utf8)!

    let job = try JSONDecoder().decode(Job.self, from: json)
    #expect(job.id == 42)
    #expect(job.finished == true)
    #expect(job.success == true)
    #expect(job.duration == 300.0)
}

@Test func decodesStatsResponse() throws {
    let json = """
    {
        "speed": 1048576,
        "bytes": 10485760,
        "errors": 0,
        "fatalError": false,
        "checks": 5,
        "transfers": 3,
        "deletes": 0,
        "elapsedTime": 10.5,
        "totalBytes": 52428800,
        "totalTransfers": 10,
        "totalChecks": 20,
        "transferring": [
            {
                "name": "file.zip",
                "size": 5242880,
                "bytes": 2621440,
                "percentage": 50,
                "speed": 524288,
                "speedAvg": 500000,
                "eta": 5,
                "group": "job/42"
            }
        ]
    }
    """.data(using: .utf8)!

    let stats = try JSONDecoder().decode(StatsResponse.self, from: json)
    #expect(stats.speed == 1_048_576)
    #expect(stats.transferring?.count == 1)
    #expect(stats.transferring?[0].percentage == 50)
}

@Test func decodesAboutResponse() throws {
    let json = """
    {
        "total": 16106127360,
        "used": 10737418240,
        "free": 5368709120
    }
    """.data(using: .utf8)!

    let about = try JSONDecoder().decode(AboutResponse.self, from: json)
    #expect(about.total == 16_106_127_360)
    #expect(about.used == 10_737_418_240)
    #expect(about.free == 5_368_709_120)
}

@Test func decodesAboutResponseWithNulls() throws {
    let json = """
    {
        "total": null,
        "used": 500
    }
    """.data(using: .utf8)!

    let about = try JSONDecoder().decode(AboutResponse.self, from: json)
    #expect(about.total == nil)
    #expect(about.used == 500)
    #expect(about.free == nil)
}

@Test func decodesBandwidthLimitResponse() throws {
    let json = """
    {
        "bytesPerSecond": 5242880,
        "bytesPerSecondTx": 5242880,
        "bytesPerSecondRx": 5242880,
        "rate": "5M"
    }
    """.data(using: .utf8)!

    let bw = try JSONDecoder().decode(BandwidthLimitResponse.self, from: json)
    #expect(bw.rate == "5M")
    #expect(bw.bytesPerSecond == 5_242_880)
}
