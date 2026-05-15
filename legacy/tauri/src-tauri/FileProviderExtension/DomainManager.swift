import FileProvider
import Foundation

// MARK: - Domain Manager CLI
// Usage:
//   fp-domain-manager add <identifier> <displayName>
//   fp-domain-manager remove <identifier>
//   fp-domain-manager list

@main
struct DomainManagerCLI {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            printUsage()
            exit(1)
        }

        let command = args[1]

        do {
            switch command {
            case "add":
                guard args.count >= 4 else { printUsage(); exit(1) }
                try await addDomain(identifier: args[2], displayName: args[3])
            case "remove":
                guard args.count >= 3 else { printUsage(); exit(1) }
                try await removeDomain(identifier: args[2])
            case "remove-all":
                try await removeAllDomains()
            case "list":
                try await listDomains()
            default:
                printUsage()
                exit(1)
            }
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func addDomain(identifier: String, displayName: String) async throws {
        let domainId = NSFileProviderDomainIdentifier(rawValue: identifier)
        let domain = NSFileProviderDomain(identifier: domainId, displayName: displayName)

        let existing = try await NSFileProviderManager.domains()
        if existing.contains(where: { $0.identifier == domainId }) {
            print("Domain '\(identifier)' already registered, updating...")
            try await NSFileProviderManager.remove(domain)
        }

        try await NSFileProviderManager.add(domain)
        print("OK: Domain '\(identifier)' (\(displayName)) registered")
    }

    static func removeDomain(identifier: String) async throws {
        let domainId = NSFileProviderDomainIdentifier(rawValue: identifier)
        let existing = try await NSFileProviderManager.domains()
        guard let domain = existing.first(where: { $0.identifier == domainId }) else {
            fputs("Domain '\(identifier)' not found\n", stderr)
            exit(1)
        }
        try await NSFileProviderManager.remove(domain)
        print("OK: Domain '\(identifier)' removed")
    }

    static func removeAllDomains() async throws {
        let domains = try await NSFileProviderManager.domains()
        for domain in domains {
            try await NSFileProviderManager.remove(domain)
            print("Removed domain: \(domain.identifier.rawValue)")
        }
        print("OK: All domains removed")
    }

    static func listDomains() async throws {
        let domains = try await NSFileProviderManager.domains()
        if domains.isEmpty {
            print("No File Provider domains registered")
            return
        }
        for domain in domains {
            print("\(domain.identifier.rawValue)\t\(domain.displayName)")
        }
    }

    static func printUsage() {
        fputs("Usage: fp-domain-manager <add|remove|remove-all|list> [args...]\n", stderr)
        fputs("  add <identifier> <displayName>  - Register a File Provider domain\n", stderr)
        fputs("  remove <identifier>             - Remove a File Provider domain\n", stderr)
        fputs("  remove-all                      - Remove all domains\n", stderr)
        fputs("  list                            - List registered domains\n", stderr)
    }
}
