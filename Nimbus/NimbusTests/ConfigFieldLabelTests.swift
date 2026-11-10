import Testing
import Foundation
@testable import Nimbus

@Suite("ConfigFieldLabel")
struct ConfigFieldLabelTests {
    @Test(arguments: [
        ("access_key_id", "Access key ID"),
        ("secret_access_key", "Secret access key"),
        ("host", "Server address"),
        ("user", "User name"),
        ("pass", "Password"),
        ("key_file", "Private key file"),
        ("client_id", "Client ID"),
        ("client_secret", "Client secret"),
        ("url", "Server URL"),
    ])
    func commonOptionsHaveWrittenLabels(name: String, expected: String) {
        #expect(ConfigFieldLabel.label(forOption: name) == expected)
    }

    @Test(arguments: [
        ("upload_cutoff", "Upload cutoff"),
        ("sse_kms_key_id", "SSE KMS key ID"),
        ("disable_http2", "Disable HTTP2"),
        ("md5sum_command", "MD5sum command"),
        ("use_mmap", "Use mmap"),
    ])
    func anythingElseIsReadableNotSnakeCase(name: String, expected: String) {
        #expect(ConfigFieldLabel.label(forOption: name) == expected)
    }

    @Test func noLabelEverContainsAnUnderscore() {
        for name in ["a_b_c", "_leading", "trailing_", "x__y", "config_fs_advanced"] {
            #expect(!ConfigFieldLabel.label(forOption: name).contains("_"), "\(name)")
        }
    }

    @Test func anEmptyNameStillGivesSomethingToShow() {
        #expect(ConfigFieldLabel.label(forOption: "") == "Setting")
    }

    @Test func aChoiceShowsItsDescriptionWhenThereIsOne() {
        #expect(ConfigFieldLabel.choiceLabel(value: "AWS", help: "Amazon Web Services (AWS) S3") == "Amazon Web Services (AWS) S3")
        #expect(ConfigFieldLabel.choiceLabel(value: "eu-west-1", help: "") == "eu-west-1")
        // Only the first line: rclone's descriptions can run to a paragraph.
        #expect(ConfigFieldLabel.choiceLabel(value: "x", help: "Short name\nA long explanation.") == "Short name")
        // An empty value is rclone's "leave blank"; its description says what that means.
        #expect(ConfigFieldLabel.choiceLabel(value: "", help: "") == "Default")
    }
}
