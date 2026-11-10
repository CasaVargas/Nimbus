import Foundation

/// The words shown for an rclone option on a setup or edit page.
///
/// rclone names options in snake_case (`access_key_id`, `key_file_pass`).
/// The ones people meet most have written labels; everything else is made
/// readable mechanically, so no page ever shows a raw option name.
enum ConfigFieldLabel {
    static func label(forOption name: String) -> String {
        if let written = written[name] { return written }
        return humanized(name)
    }

    /// What a pop-up menu shows for one of an option's suggested values:
    /// rclone's description of it when there is one, otherwise the value.
    static func choiceLabel(value: String, help: String) -> String {
        let firstLine = help
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        if let firstLine { return firstLine }
        return value.isEmpty ? "Default" : value
    }

    private static let written: [String: String] = [
        // Sign-in plumbing (OAuth services, "Show all options")
        "client_id": "Client ID",
        "client_secret": "Client secret",
        "scope": "Access level",
        "root_folder_id": "Root folder ID",
        "service_account_file": "Service account file",
        "team_drive": "Shared drive ID",
        "auth_url": "Sign-in URL",
        "token_url": "Token URL",
        // S3 and compatible
        "provider": "Provider",
        "env_auth": "Use credentials from this Mac",
        "access_key_id": "Access key ID",
        "secret_access_key": "Secret access key",
        "region": "Region",
        "endpoint": "Endpoint",
        "location_constraint": "Location constraint",
        "acl": "Access control",
        "server_side_encryption": "Server-side encryption",
        "storage_class": "Storage class",
        "bucket_acl": "Bucket access control",
        // SFTP, FTP, WebDAV and other servers
        "host": "Server address",
        "user": "User name",
        "port": "Port",
        "pass": "Password",
        "key_file": "Private key file",
        "key_file_pass": "Private key passphrase",
        "key_pem": "Private key",
        "key_use_agent": "Use the SSH agent",
        "known_hosts_file": "Known hosts file",
        "url": "Server URL",
        "vendor": "Server type",
        "bearer_token": "Bearer token",
        "tls": "Use TLS",
        "explicit_tls": "Use explicit TLS",
        // Backblaze B2 and similar key pairs
        "account": "Account ID",
        "key": "Application key",
        "hard_delete": "Delete files permanently",
        // Encryption wrapper
        "remote": "Cloud and folder",
        "filename_encryption": "File name encryption",
        "directory_name_encryption": "Encrypt folder names",
        "password": "Password",
        "password2": "Salt password",
    ]

    /// Kept upper-case wherever they appear as a word.
    private static let acronyms: Set<String> = [
        "id", "url", "ssh", "api", "acl", "kms", "sse", "tls", "ssl", "http", "https", "ftp", "sftp",
        "s3", "b2", "iam", "sts", "arn", "nfs", "smb", "dns", "ip", "uid", "gid", "utf8", "oauth", "jwt", "pem",
    ]

    private static func humanized(_ name: String) -> String {
        let words = name.split(separator: "_").map(String.init)
        guard !words.isEmpty else { return "Setting" }
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            if acronyms.contains(lower) { return lower.uppercased() }
            // "http2", "md5sum": keep a leading acronym's letters upper-case.
            if let split = lower.firstIndex(where: \.isNumber) {
                let head = String(lower[..<split])
                if acronyms.contains(head) || head == "md" || head == "sha" {
                    return head.uppercased() + lower[split...]
                }
            }
            return index == 0 ? lower.prefix(1).uppercased() + lower.dropFirst() : lower
        }
        .joined(separator: " ")
    }
}
