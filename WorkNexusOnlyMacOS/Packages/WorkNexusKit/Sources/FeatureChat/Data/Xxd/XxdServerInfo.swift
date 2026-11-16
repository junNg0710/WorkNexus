import Foundation

/// Login parameters for one xxd account.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_server_info.dart
public struct XxdCredentials: Sendable, Equatable {
    /// xxd HTTPS origin, e.g. `https://zentao.example.com:11443`.
    public var server: URL
    public var account: String
    public var password: String
    /// Empty for the default server configured in xxd.
    public var serverName: String
    /// Trusted SHA-256 certificate fingerprint for a self-signed xxd.
    public var pinnedFingerprint: String?

    public init(server: URL, account: String, password: String, serverName: String = "", pinnedFingerprint: String? = nil) {
        self.server = server; self.account = account; self.password = password
        self.serverName = serverName; self.pinnedFingerprint = pinnedFingerprint
    }
}

/// The `sysgetserverinfo` reply: session token and how to reach the socket.
public struct XxdServerInfo: Sendable {
    public var token: String
    public var chatPort: Int
    public var version: String
    public var enableClientAes: Bool
    public var socketUrl: String?
    public var apiScheme: JSONObject?
    public var uploadFileSize: Int?
    public var backendUrl: String?
    /// Short-lived key for ZenTao web calls through `im-authorize`.
    public var authToken: String?
    /// ZenTao URL style: `PATH_INFO` (`module-method-args.html`) or `GET` (`index.php?m=&f=`), and the PATH_INFO separator.
    public var requestType = "PATH_INFO"
    public var requestFix = "-"
    /// The server's clock when it answered, for keys that change over time.
    public var serverTime: Date?
    /// Seconds an `im-authorize` key derived from `authToken` stays valid.
    public var authTokenWindow = 20

    /// Returns nil when the reply carries no token (login rejected).
    public static func tryParse(_ json: JSONObject) -> XxdServerInfo? {
        guard let token = json["token"]?.string, !token.isEmpty else { return nil }
        func str(_ k: String) -> String? { json["\(k)"]?.string }
        var info = XxdServerInfo(
            token: token, chatPort: json["chatPort"]?.intValue ?? 11444,
            version: json["version"].map { JS.toString($0) } ?? "",
            enableClientAes: truthy(json["enableClientAES"]))
        if let s = str("socketUrl"), !s.isEmpty { info.socketUrl = s }
        info.apiScheme = json["apiScheme"]?.object
        info.uploadFileSize = json["uploadFileSize"]?.intValue
        info.backendUrl = str("backendURL")
        info.authToken = str("authToken")
        info.requestType = json["requestType"].map { JS.toString($0) } ?? "PATH_INFO"
        info.requestFix = json["requestFix"].map { JS.toString($0) } ?? "-"
        info.serverTime = date(json["serverTime"])
        info.authTokenWindow = json["authTokenAuthWindow"]?.intValue ?? 20
        return info
    }

    /// `socketUrl` when given, else `wss://<host>:<chatPort>/ws`.
    public func socketURL(server: URL) -> URL? {
        if let socketUrl { return URL(string: socketUrl) }
        var c = URLComponents()
        c.scheme = server.scheme == "https" ? "wss" : "ws"
        c.host = server.host
        c.port = chatPort
        c.path = "/ws"
        return c.url
    }

    /// Unix seconds or milliseconds, or an ISO date string.
    private static func date(_ v: JSONValue?) -> Date? {
        guard let v else { return nil }
        if let n = v.intValue, n > 0 { return Date(timeIntervalSince1970: n < 100_000_000_000 ? Double(n) : Double(n) / 1000) }
        if let s = v.string {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)
        }
        return nil
    }

    private static func truthy(_ v: JSONValue?) -> Bool {
        switch v {
        case .bool(true)?: return true
        case .int(let i)?: return i != 0
        case .double(let d)?: return d != 0
        case .string(let s)?: return s == "1" || s == "true"
        default: return false
        }
    }
}
