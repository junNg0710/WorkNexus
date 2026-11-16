import CommonCrypto
import Foundation

public enum XxdCipherError: Error, Equatable { case badKey(String), badCiphertext(String) }

/// AES-256-CBC (PKCS7) for xxd socket frames when `serverInfo` returns `enableClientAES`.
/// Key = the 32-char session token, IV = its first 16 chars (UTF-8 bytes, like Node's `createCipheriv` with string keys).
/// Padding is applied here (CommonCrypto runs raw CBC) so malformed ciphertext is rejected explicitly.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_cipher.dart
public struct XxdCipher: Sendable {
    private static let block = 16
    private let key: [UInt8]
    private let iv: [UInt8]

    public init(token: String) throws {
        let bytes = Array(token.utf8)
        guard bytes.count == 32 else { throw XxdCipherError.badKey("token must be 32 bytes for AES-256 (got \(bytes.count))") }
        key = bytes
        iv = Array(bytes.prefix(Self.block))
    }

    public func encrypt(_ plain: String) -> Data {
        let data = Array(plain.utf8)
        let pad = Self.block - data.count % Self.block
        return Data(run(data + [UInt8](repeating: UInt8(pad), count: pad), encrypt: true) ?? [])
    }

    public func decrypt(_ cipher: Data) throws -> String {
        guard !cipher.isEmpty, cipher.count % Self.block == 0 else {
            throw XxdCipherError.badCiphertext("Ciphertext length \(cipher.count) is not a multiple of \(Self.block)")
        }
        guard let plain = run([UInt8](cipher), encrypt: false), let last = plain.last else {
            throw XxdCipherError.badCiphertext("Decryption failed")
        }
        let pad = Int(last)
        guard pad >= 1, pad <= Self.block, plain.suffix(pad).allSatisfy({ Int($0) == pad }) else {
            throw XxdCipherError.badCiphertext("Bad PKCS7 padding (wrong key?)")
        }
        guard let s = String(bytes: plain.dropLast(pad), encoding: .utf8) else {
            throw XxdCipherError.badCiphertext("Plaintext is not UTF-8")
        }
        return s
    }

    private func run(_ input: [UInt8], encrypt: Bool) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: input.count + Self.block)
        var moved = 0
        let status = CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0,
                             key, key.count, iv, input, input.count, &out, out.count, &moved)
        guard status == kCCSuccess else { return nil }
        return Array(out.prefix(moved))
    }
}
