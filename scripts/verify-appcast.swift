// Checks a release's appcast against its DMG and the key the app trusts (#100).
//
//   swift scripts/verify-appcast.swift <appcast.xml> <dmg> <SUPublicEDKey>
//
// Sparkle refuses an update whose EdDSA signature does not verify with the
// SUPublicEDKey of the installed app. A wrong secret, or a DMG changed after
// signing (re-stapled, rebuilt), would publish an update nobody can install;
// this fails the release instead. It does not use Sparkle, so it also checks
// Sparkle's own sign_update.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4 else { fail("usage: verify-appcast.swift <appcast.xml> <dmg> <SUPublicEDKey>") }

guard let document = try? XMLDocument(contentsOf: URL(fileURLWithPath: args[1])),
      let enclosure = try? document.nodes(forXPath: "//item/enclosure").first as? XMLElement else {
    fail("\(args[1]) has no enclosure")
}
guard let dmg = try? Data(contentsOf: URL(fileURLWithPath: args[2])) else { fail("cannot read \(args[2])") }

func attribute(_ name: String) -> String {
    guard let value = enclosure.attribute(forName: name)?.stringValue, !value.isEmpty else {
        fail("the enclosure has no \(name)")
    }
    return value
}

let url = attribute("url")
let dmgName = URL(fileURLWithPath: args[2]).lastPathComponent
guard url.hasPrefix("https://"), url.hasSuffix("/" + dmgName) else {
    fail("the enclosure url \(url) does not point at \(dmgName) over https")
}
guard Int(attribute("length")) == dmg.count else {
    fail("the enclosure length \(attribute("length")) is not the DMG's size \(dmg.count)")
}
guard let keyData = Data(base64Encoded: args[3]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("SUPublicEDKey is not an ed25519 public key: \(args[3])")
}
guard let signature = Data(base64Encoded: attribute("sparkle:edSignature")) else {
    fail("sparkle:edSignature is not base64")
}
guard key.isValidSignature(signature, for: dmg) else {
    fail("the signature does not verify with the app's SUPublicEDKey. Is SPARKLE_PRIVATE_KEY the key that matches it, and was the DMG changed after signing?")
}
print("verify-appcast: OK (\(dmgName), \(dmg.count) bytes)")
