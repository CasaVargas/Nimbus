import Testing
import Foundation
import RcloneKit
@testable import Nimbus

private func option(
    _ name: String, type: String = "string", isPassword: Bool = false,
    sensitive: Bool = false, hide: Int = 0
) -> ProviderOption {
    let json = #"""
    {"Name": "\#(name)", "Help": "", "Type": "\#(type)", "Required": false,
     "IsPassword": \#(isPassword), "Advanced": false, "Sensitive": \#(sensitive),
     "Hide": \#(hide), "Exclusive": false, "Default": "", "DefaultStr": "", "Value": null}
    """#
    return try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
}

private func boolOption(default defaultValue: String) -> ProviderOption {
    let json = #"""
    {"Name": "bool_opt", "Help": "", "Type": "bool", "Required": false,
     "IsPassword": false, "Advanced": false, "Sensitive": false,
     "Hide": 0, "Exclusive": false, "Default": "\#(defaultValue)", "DefaultStr": "", "Value": null}
    """#
    return try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
}

@Suite("ConfigFieldView")
@MainActor
struct ConfigFieldViewTests {

    @Test func passwordOptionsAreSecure() {
        #expect(ConfigFieldView.isSecure(option("pass", isPassword: true)))
    }

    @Test func sensitiveOptionsAreAlsoSecure() {
        // SFTP's key_file_pass is Sensitive but not IsPassword — it rendered
        // in the clear before this.
        #expect(ConfigFieldView.isSecure(option("key_file_pass", sensitive: true)))
    }

    /// #162: rclone marks iCloud's apple_id (and SFTP/SMB host/user) as
    /// Sensitive, but they are identifiers — masking them hid the Apple ID.
    @Test func sensitiveIdentifiersAreNotSecure() {
        for name in ["apple_id", "user", "username", "email", "host"] {
            #expect(!ConfigFieldView.isSecure(option(name, sensitive: true)), "\(name)")
        }
    }

    @Test func sensitiveSecretsStaySecure() {
        for name in ["secret_access_key", "api_key", "client_secret", "key"] {
            #expect(ConfigFieldView.isSecure(option(name, sensitive: true)), "\(name)")
        }
    }

    @Test func passwordIsSecureEvenWithAnIdentifierName() {
        #expect(ConfigFieldView.isSecure(option("user", isPassword: true)))
    }

    @Test func ordinaryOptionsAreNotSecure() {
        #expect(!ConfigFieldView.isSecure(option("host")))
    }

    @Test func hiddenOptionsAreNotRendered() {
        #expect(!ConfigFieldView.shouldRender(option("internal_thing", hide: 1)))
        #expect(ConfigFieldView.shouldRender(option("host")))
    }

    // An unanswered option is stored as "" (rclone's config/dump only persists
    // keys that were explicitly set) — it must fall back to the provider's own
    // default rather than reading as "off".
    @Test func unansweredDefaultTrueBoolIsOn() {
        #expect(ConfigFieldView.isOn("", option: boolOption(default: "true")))
    }

    @Test func explicitFalseBeatsDefaultTrue() {
        #expect(!ConfigFieldView.isOn("false", option: boolOption(default: "true")))
    }

    @Test func unansweredDefaultFalseBoolIsOff() {
        #expect(!ConfigFieldView.isOn("", option: boolOption(default: "false")))
    }

    @Test func explicitTrueBeatsDefaultFalse() {
        #expect(ConfigFieldView.isOn("true", option: boolOption(default: "false")))
    }
}
