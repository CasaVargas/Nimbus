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

@Suite("ConfigFieldView")
struct ConfigFieldViewTests {

    @Test func passwordOptionsAreSecure() {
        #expect(ConfigFieldView.isSecure(option("pass", isPassword: true)))
    }

    @Test func sensitiveOptionsAreAlsoSecure() {
        // SFTP's key_file_pass is Sensitive but not IsPassword — it rendered
        // in the clear before this.
        #expect(ConfigFieldView.isSecure(option("key_file_pass", sensitive: true)))
    }

    @Test func ordinaryOptionsAreNotSecure() {
        #expect(!ConfigFieldView.isSecure(option("host")))
    }

    @Test func hiddenOptionsAreNotRendered() {
        #expect(!ConfigFieldView.shouldRender(option("internal_thing", hide: 1)))
        #expect(ConfigFieldView.shouldRender(option("host")))
    }
}
