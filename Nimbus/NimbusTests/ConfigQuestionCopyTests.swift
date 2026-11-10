import Testing
import Foundation
import RcloneKit
@testable import Nimbus

@Suite("ConfigQuestionCopy")
struct ConfigQuestionCopyTests {
    private func option(_ name: String, help: String = "", type: String = "string",
                        examples: [(String, String)] = []) -> ProviderOption {
        let list = examples.map { #"{"Value":"\#($0.0)","Help":"\#($0.1)"}"# }.joined(separator: ",")
        let examplesJSON = examples.isEmpty ? "" : #", "Examples": [\#(list)]"#
        let json = #"""
        {"Name": "\#(name)", "Help": "\#(help)", "Type": "\#(type)", "Required": false,
         "IsPassword": false, "Advanced": false, "Sensitive": false, "Hide": 0,
         "Exclusive": true, "Default": "", "DefaultStr": "", "Value": null\#(examplesJSON)}
        """#
        return try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
    }

    @Test func driveSharedDriveQuestionIsWrittenInPlainWords() {
        let copy = ConfigQuestionCopy.copy(for: option(
            "config_change_team_drive", help: "Configure this as a Shared Drive (Team Drive)?\\n",
            type: "bool", examples: [("true", "Yes"), ("false", "No")]))
        #expect(copy.title == "Which drive is this?")
        // "My Drive" first: it is rclone's default and what most people want.
        #expect(copy.choices.map(\.value) == ["false", "true"])
        #expect(copy.choices.map(\.title) == ["My Drive", "A shared drive"])
        #expect(copy.choices.allSatisfy { $0.detail != nil })
    }

    @Test func unknownQuestionUsesRclonesHelpAsItsTitle() {
        let copy = ConfigQuestionCopy.copy(for: option(
            "config_type", help: "Type of connection\\nChoose one of the following.",
            examples: [("onedrive", "OneDrive Personal or Business"), ("sharepoint", "Root Sharepoint site")]))
        #expect(copy.title == "Type of connection")
        #expect(copy.choices.map(\.title) == ["OneDrive Personal or Business", "Root Sharepoint site"])
        #expect(copy.choices.map(\.value) == ["onedrive", "sharepoint"])
    }

    @Test func anOptionNameIsNeverShownEvenWithNoHelp() {
        let copy = ConfigQuestionCopy.copy(for: option("config_mystery_setting"))
        #expect(!copy.title.contains("config_"))
        #expect(!copy.title.isEmpty)
    }

    @Test func aChoiceWithoutADescriptionFallsBackToItsValue() {
        let copy = ConfigQuestionCopy.copy(for: option("config_region", help: "Region", examples: [("eu", ""), ("us", "")]))
        #expect(copy.choices.map(\.title) == ["eu", "us"])
    }

    @Test func aYesNoQuestionWithoutExamplesStillGetsTwoChoices() {
        let copy = ConfigQuestionCopy.copy(for: option("config_something", help: "Do the thing?", type: "bool"))
        #expect(copy.choices.map(\.value) == ["true", "false"])
        #expect(copy.choices.map(\.title) == ["Yes", "No"])
    }

    @Test func aFreeTextQuestionHasNoChoices() {
        let copy = ConfigQuestionCopy.copy(for: option("config_name", help: "Name of the thing"))
        #expect(copy.choices.isEmpty)
    }
}
