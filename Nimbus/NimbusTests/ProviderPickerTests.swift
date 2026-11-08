import Testing
import SwiftUI
import RcloneKit
@testable import Nimbus

/// Snapshot coverage for the Add Remote provider list. `Provider` has no
/// public memberwise init (it's decode-only), so fixtures decode the same
/// JSON shape rclone's `config/providers` returns.
@Suite("ProviderPicker", .serialized)
@MainActor
struct ProviderPickerTests {
    private func provider(_ name: String, _ description: String) throws -> Provider {
        let json = #"{"Name":"\#(name)","Description":"\#(description)","Prefix":"\#(name)","Options":[]}"#
        return try JSONDecoder().decode(Provider.self, from: Data(json.utf8))
    }

    private func sampleProviders() throws -> [Provider] {
        try [
            provider("drive", "Google Drive"),
            provider("dropbox", "Dropbox"),
            provider("onedrive", "Microsoft OneDrive"),
            provider("iclouddrive", "iCloud Drive"),
            provider("s3", "Amazon S3 Compliant Storage Providers"),
            provider("box", "Box"),
            provider("mega", "Mega"),
            provider("protondrive", "Proton Drive"),
            provider("sftp", "SSH/SFTP"),
            provider("webdav", "WebDAV"),
            provider("crypt", "Encrypt/Decrypt a remote"),
            provider("pcloud", "Pcloud"),
            provider("b2", "Backblaze B2"),
        ]
    }

    @Test func rendersPopularAndAllSections() throws {
        let view = ProviderPicker(providers: try sampleProviders(), onPick: { _ in })
            .frame(width: 520)
            .padding()
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 552, height: 640),
            named: "ProviderPicker-sections"
        )
    }
    @Test func catalogKeepsOrderAndSkipsMissingServices() throws {
        let popular = PickerCatalog.entries(PickerCatalog.popular, in: try sampleProviders())
        #expect(popular.map(\.title) == ["Google Drive", "OneDrive", "Dropbox", "iCloud Drive",
                                          "Box", "pCloud", "Proton Drive", "MEGA"])
        #expect(popular.first?.hint == "Sign in with Google")
        let servers = PickerCatalog.entries(PickerCatalog.servers, in: try [provider("sftp", "SSH/SFTP")])
        #expect(servers.map(\.title) == ["NAS or server (SFTP)"])
    }

    @Test func oauthCatalogMatchesBrowserSignInBackends() {
        for prefix in ["drive", "dropbox", "onedrive", "box", "pcloud"] {
            #expect(PickerCatalog.isOAuth(prefix))
        }
        for prefix in ["s3", "sftp", "mega", "protondrive", "iclouddrive"] {
            #expect(!PickerCatalog.isOAuth(prefix))
        }
    }
}
