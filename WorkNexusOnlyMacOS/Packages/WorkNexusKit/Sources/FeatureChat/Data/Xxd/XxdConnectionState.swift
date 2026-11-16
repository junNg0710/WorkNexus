import CoreDomain
import Foundation

/// The logged-in xxd session.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_connection_state.dart
public struct XxdSession: Sendable {
    /// The `userlogin` reply data (`id`, `account`, `realname`, `avatar`, …).
    public var user: JSONObject
    public var serverVersion: String
    /// HTTP session id from `syssessionid`; signs file downloads.
    public var sessionId: String?
    /// Session token from `serverInfo`; authorizes file uploads.
    public var token: String
    /// Largest upload the server accepts, in bytes (nil = unknown).
    public var uploadFileSize: Int?

    public init(user: JSONObject, serverVersion: String, sessionId: String? = nil, token: String = "", uploadFileSize: Int? = nil) {
        self.user = user; self.serverVersion = serverVersion; self.sessionId = sessionId
        self.token = token; self.uploadFileSize = uploadFileSize
    }

    public var userId: Int { user["id"]?.intValue ?? 0 }
    func withSessionId(_ id: String) -> XxdSession { var s = self; s.sessionId = id; return s }
}

/// Lifecycle of an xxd connection.
public enum XxdConnectionState: Sendable {
    /// Not started, or stopped by the caller.
    case disconnected
    case connecting
    case online(XxdSession)
    /// The socket dropped; the next attempt runs after `delay`.
    case reconnecting(attempt: Int, delay: TimeInterval, lastFailure: Failure)
    /// Gave up: bad credentials, untrusted certificate, or kicked by another login. Needs user action before reconnecting.
    case stopped(Failure, kicked: Bool)

    public var isOnline: Bool { if case .online = self { true } else { false } }
    public var session: XxdSession? { if case .online(let s) = self { s } else { nil } }
}
