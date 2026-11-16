import CommonCrypto
import Foundation

/// Ported from: lib/features/mini_apps/data/datasources/browser_cookies/chromium_cookie_crypto.dart
/// How Chromium on macOS encrypts a cookie's value: AES-128-CBC under a key derived (PBKDF2-HMAC-SHA1, salt `saltysalt`,
/// 1003 iterations, 16 bytes) from a password it keeps in the system keychain, with a fixed IV of 16 spaces. Values start
/// with `v10` (or `v11`).
public struct ChromiumCookieCrypto: Sendable {
    private let key: Data
    private static let block = 16

    public init(key: Data) { self.key = key }

    /// The key Chromium derives from its keychain `password`.
    public init(password: String) {
        var derived = Data(count: Self.block)
        let salt = Array("saltysalt".utf8), pw = Array(password.utf8)
        _ = derived.withUnsafeMutableBytes { out in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count, salt, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                 out.bindMemory(to: UInt8.self).baseAddress, Self.block)
        }
        self.init(key: derived)
    }

    var keyBytes: Data { key }

    /// The value Chromium wrote as `encrypted`. From database version 24 on it starts with the SHA-256 of the cookie's
    /// domain, which `hasDomainHash` drops. nil for a value it cannot decrypt (another scheme or key).
    public func decrypt(_ encrypted: Data, hasDomainHash: Bool) -> String? {
        let enc = [UInt8](encrypted)
        guard enc.count >= 3 + Self.block, let prefix = String(bytes: enc[0..<3], encoding: .ascii), prefix == "v10" || prefix == "v11" else { return nil }
        let body = Array(enc[3...])
        guard body.count % Self.block == 0 else { return nil }
        var plain = [UInt8](repeating: 0, count: body.count)
        var moved = 0
        let iv = [UInt8](repeating: 0x20, count: Self.block)
        let status = key.withUnsafeBytes { k in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0 /* CBC, no padding: stripped below */, k.baseAddress, Self.block, iv,
                    body, body.count, &plain, plain.count, &moved)
        }
        guard status == kCCSuccess, moved == body.count, let pad = plain.last, pad >= 1, Int(pad) <= Self.block else { return nil }
        let end = plain.count - Int(pad)
        let start = hasDomainHash ? 32 : 0
        guard end >= start else { return nil }
        return String(decoding: plain[start..<end], as: UTF8.self)
    }

    /// Test helper: encrypts like Chromium does (PKCS#7, same IV), to build fixtures independently of `decrypt`.
    func encryptForTesting(_ plain: [UInt8], prefix: String = "v10") -> Data {
        let pad = Self.block - plain.count % Self.block
        let padded = plain + [UInt8](repeating: UInt8(pad), count: pad)
        var out = [UInt8](repeating: 0, count: padded.count)
        var moved = 0
        let iv = [UInt8](repeating: 0x20, count: Self.block)
        _ = key.withUnsafeBytes { k in
            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), 0, k.baseAddress, Self.block, iv, padded, padded.count, &out, out.count, &moved)
        }
        return Data(prefix.utf8) + Data(out)
    }
}
