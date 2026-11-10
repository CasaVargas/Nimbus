import Foundation
import RcloneKit

/// The words Nimbus shows for a question rclone asks after sign-in.
///
/// rclone identifies these by option names such as
/// `config_change_team_drive`, which must never reach the screen. Questions
/// people actually meet get written copy in `written`; anything else falls
/// back to rclone's own help text and example descriptions.
struct ConfigQuestionCopy: Equatable {
    struct Choice: Equatable, Identifiable {
        /// What is sent back to rclone.
        let value: String
        let title: String
        let detail: String?

        var id: String { value }
    }

    let title: String
    /// Empty for a question that needs typing rather than choosing.
    let choices: [Choice]

    static func copy(for option: ProviderOption) -> ConfigQuestionCopy {
        if let written = written[option.name] { return written }
        return ConfigQuestionCopy(title: fallbackTitle(option), choices: fallbackChoices(option))
    }

    private static let written: [String: ConfigQuestionCopy] = [
        "config_change_team_drive": ConfigQuestionCopy(
            title: "Which drive is this?",
            choices: [
                Choice(value: "false", title: "My Drive",
                       detail: "The files in your own Google account."),
                Choice(value: "true", title: "A shared drive",
                       detail: "A team space your organization owns. You pick which one next."),
            ]
        ),
    ]

    /// The first line of rclone's help, without the trailing colon some
    /// options carry. Never the option name.
    private static func fallbackTitle(_ option: ProviderOption) -> String {
        let firstLine = option.help
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let trimmed = firstLine.hasSuffix(":") ? String(firstLine.dropLast()) : firstLine
        return trimmed.isEmpty ? "One more question" : trimmed
    }

    private static func fallbackChoices(_ option: ProviderOption) -> [Choice] {
        if let examples = option.examples, !examples.isEmpty {
            return examples.map { example in
                let description = example.help.trimmingCharacters(in: .whitespacesAndNewlines)
                return Choice(value: example.value, title: description.isEmpty ? example.value : description, detail: nil)
            }
        }
        if option.type == "bool" {
            return [Choice(value: "true", title: "Yes", detail: nil), Choice(value: "false", title: "No", detail: nil)]
        }
        return []
    }
}
