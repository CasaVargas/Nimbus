import CommonCrypto
import Foundation

/// rclone's reversible password obscuring (`rclone obscure` / `lib/obscure`).
///
/// Answers to `IsPassword` questions in the `config/create` state machine are
/// written to rclone.conf VERBATIM — `opt.obscure` only applies to
/// `parameters`, not to `opt.result` (verified on rclone 1.75.1). Backends
/// then `Reveal` the stored value, so a plaintext answer fails with "input
/// too short when revealing password - is it obscured?" (#109). Callers must
/// obscure password answers themselves before sending them.
///
/// Format: base64url (no padding) of a random 16-byte IV followed by the
/// AES-256-CTR encryption of the UTF-8 plaintext under rclone's fixed key.
public enum RcloneObscure {
    private static let key: [UInt8] = [
        0x9c, 0x93, 0x5b, 0x48, 0x73, 0x0a, 0x55, 0x4d,
        0x6b, 0xfd, 0x7c, 0x63, 0xc8, 0x86, 0xa9, 0x2b,
        0xd3, 0x90, 0x19, 0x8e, 0xb8, 0x12, 0x8a, 0xfb,
        0xf4, 0xde, 0x16, 0x2b, 0x8b, 0x95, 0xf6, 0x38,
    ]
    private static let blockSize = kCCBlockSizeAES128

    public static func obscure(_ clear: String) -> String {
        var iv = Data(count: blockSize)
        let status = iv.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, blockSize, $0.baseAddress!)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return obscure(clear, iv: iv)
    }

    /// Returns nil when `obscured` isn't something rclone could reveal.
    public static func reveal(_ obscured: String) -> String? {
        guard let raw = decodeBase64URL(obscured), raw.count >= blockSize else { return nil }
        let iv = raw.prefix(blockSize)
        let clear = ctr(Data(raw.dropFirst(blockSize)), iv: Data(iv))
        return String(data: clear, encoding: .utf8)
    }

    static func obscure(_ clear: String, iv: Data) -> String {
        encodeBase64URL(iv + ctr(Data(clear.utf8), iv: iv))
    }

    /// AES-256-CTR, big-endian counter (Go's `cipher.NewCTR`). CTR is its
    /// own inverse, so this both encrypts and decrypts.
    private static func ctr(_ input: Data, iv: Data) -> Data {
        guard !input.isEmpty else { return Data() }
        var cryptor: CCCryptorRef?
        let created = iv.withUnsafeBytes { ivPtr in
            key.withUnsafeBytes { keyPtr in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding), ivPtr.baseAddress, keyPtr.baseAddress, key.count,
                    nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor
                )
            }
        }
        precondition(created == kCCSuccess, "CCCryptorCreateWithMode failed: \(created)")
        defer { CCCryptorRelease(cryptor) }
        var output = Data(count: input.count)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outPtr in
            input.withUnsafeBytes { inPtr in
                CCCryptorUpdate(
                    cryptor, inPtr.baseAddress, input.count,
                    outPtr.baseAddress, input.count, &moved
                )
            }
        }
        precondition(status == kCCSuccess && moved == input.count, "CCCryptorUpdate failed: \(status)")
        return output
    }

    static func decodeBase64URL(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        return Data(base64Encoded: b64)
    }

    private static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
