import CryptoKit
import Foundation

/// Ported from: lib/features/chat/data/datasources/xxd/xxd_signing.dart
public enum XxdSigning {
    static func md5(_ input: String) -> String {
        Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Auth key xxd expects for a password login: md5 hex of the password (sent in `sysgetserverinfo` and `userLogin`).
    public static func passwordAuthKey(_ password: String) -> String { md5(password) }

    /// `sid` query parameter that signs a `fileDownload` URL: md5(sessionID + fileName).
    public static func fileSid(sessionId: String, fileName: String) -> String { md5(sessionId + fileName) }

    /// The key `im-authorize` checks, derived from the server info's `authToken` like the official client's
    /// `authKeyForServer`: a 64-char token is hashed with the account and the current `window`-second slot of the
    /// server's clock; a shorter one is cut to 32 chars. The key is that value followed by its own md5.
    public static func authorizeKey(account: String, authToken: String, serverNow: Date, window: Int = 20) -> String {
        let millis = (serverNow.timeIntervalSince1970 * 1000).rounded()
        let slot = Int((millis / 1000 / Double(window)).rounded())
        let base: String
        if authToken.count == 64 { base = md5("\(account)\(authToken)\(slot)") }
        else { base = authToken.count >= 32 ? String(authToken.prefix(32)) : authToken }
        return base + md5(base)
    }
}
