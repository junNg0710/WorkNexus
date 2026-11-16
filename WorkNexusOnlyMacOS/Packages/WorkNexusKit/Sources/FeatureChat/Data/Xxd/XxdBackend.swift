import CoreDomain
import Foundation

/// ZenTao web calls an xxd client makes as the signed-in user, through `im-authorize` (ZenTao logs the request in with the
/// server info's `authToken`, then runs the wrapped action). Cookies and the 307 hop are handled by hand because the
/// sign-in answers with a redirect that must be re-POSTed with the session cookie.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_backend.dart
public struct XxdBackend: Sendable {
    public init() {}

    /// The `im-authorize` link running ZenTao `module`/`method` as `account`. The token is the key derived from the
    /// server info's `authToken` (`XxdSigning.authorizeKey`); `now` defaults to the server's clock in `info`.
    public static func authorizeURL(_ info: XxdServerInfo, account: String, module: String, method: String,
                                    params: [(String, String)] = [], now: Date? = nil) -> URL? {
        guard let backend = info.backendUrl, let authToken = info.authToken, !authToken.isEmpty else { return nil }
        let token = XxdSigning.authorizeKey(account: account, authToken: authToken,
                                            serverNow: now ?? info.serverTime ?? Date(), window: info.authTokenWindow)
        let base = backend.hasSuffix("/") ? backend : backend + "/"
        let pathInfo = info.requestType == "PATH_INFO"
        // The wrapped action uses "_" so it survives as one PATH_INFO argument; `im-authorize` turns them back.
        let target = pathInfo
            ? ([module, method] + params.map(\.1)).joined(separator: "_") + ".html"
            : "index.php?m=\(module)&f=\(method)" + params.map { "&\($0.0)=\($0.1)" }.joined()
        let args = [("account", account), ("token", token), ("device", "desktop"), ("url", target)]
        let fix = info.requestFix
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))) ?? s }
        let text = pathInfo
            ? "\(base)im\(fix)authorize\(fix)" + args.map { enc($0.1) }.joined(separator: fix) + ".html"
            : "\(base)index.php?m=im&f=authorize" + args.map { "&\($0.0)=\(enc($0.1))" }.joined()
        return URL(string: text)
    }

    /// Uploads a group picture (PNG/JPEG) through `authorize`; returns the image id `chatsetavatar` takes.
    public func uploadChatAvatar(_ authorize: URL, image: Data, pinnedFingerprint: String? = nil) async -> Outcome<String> {
        let text = await postImage(authorize, field: "imgFile", image: image, pinnedFingerprint: pinnedFingerprint)
        guard case .success(let reply) = text else { return .failure(text.failure!) }
        let id = (try? JSONValue.parse(reply))?["id"]
        guard let id, !id.isNull, !JS.toString(id).isEmpty else { return .failure(.unexpected("ZenTao did not accept the picture")) }
        return .success(JS.toString(id))
    }

    /// Uploads the user's own picture (PNG) through an `authorize` link to `my-uploadAvatar`; returns the stored file id.
    public func uploadUserAvatar(_ authorize: URL, png: Data, pinnedFingerprint: String? = nil) async -> Outcome<String> {
        // `user->uploadAvatar()` reads the file from the default field, `files`.
        let text = await postImage(authorize, field: "files", image: png, pinnedFingerprint: pinnedFingerprint)
        guard case .success(let reply) = text else { return .failure(text.failure!) }
        guard let id = Self.userAvatarFileId(reply) else { return .failure(.unexpected("ZenTao did not accept the picture")) }
        return .success(id)
    }

    /// The file id in a `my-uploadAvatar` reply: `fileID` where present, else the id in the `user-cropavatar` link.
    public static func userAvatarFileId(_ reply: String) -> String? {
        if let json = try? JSONValue.parse(reply) {
            if json["result"]?.string == "fail" { return nil }
            if let id = json["fileID"], !id.isNull, !JS.toString(id).isEmpty { return JS.toString(id) }
        }
        guard let re = try? NSRegularExpression(pattern: #"cropavatar\D*?(\d+)"#, options: .caseInsensitive),
              let m = re.firstMatch(in: reply, range: NSRange(reply.startIndex..., in: reply)),
              let r = Range(m.range(at: 1), in: reply) else { return nil }
        return String(reply[r])
    }

    /// Makes an uploaded picture the avatar through an `authorize` link to `user-cropAvatar` (whole square image).
    public func cropUserAvatar(_ authorize: URL, size: Int, pinnedFingerprint: String? = nil) async -> Outcome<Void> {
        let pairs = [("left", "0"), ("top", "0"), ("right", "\(size)"), ("bottom", "\(size)"), ("width", "\(size)"),
                     ("height", "\(size)"), ("originWidth", "\(size)"), ("originHeight", "\(size)"),
                     ("scaleWidth", "\(size)"), ("scaleHeight", "\(size)"), ("scaled", "0")]
        let body = Data(pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&").utf8)
        let text = await post(authorize, contentType: "application/x-www-form-urlencoded", body: body, pinnedFingerprint: pinnedFingerprint)
        guard case .success(let reply) = text else { return .failure(text.failure!) }
        if (try? JSONValue.parse(reply))?["result"]?.string == "success" { return .success(()) }
        return .failure(.unexpected("ZenTao did not save the picture"))
    }

    private func postImage(_ url: URL, field: String, image: Data, pinnedFingerprint: String?) async -> Outcome<String> {
        let boundary = "----worknexus\(Int(Date().timeIntervalSince1970 * 1_000_000))"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"avatar.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return await post(url, contentType: "multipart/form-data; boundary=\(boundary)", body: body, pinnedFingerprint: pinnedFingerprint)
    }

    /// POSTs `body`, following up to 5 hops by hand: `im-authorize` signs the user in (setting the ZenTao session
    /// cookie) and answers 307 to the wrapped action; the body is re-sent with the cookies gathered so far.
    func post(_ url: URL, contentType: String, body: Data, pinnedFingerprint: String?) async -> Outcome<String> {
        let policy = XxdTLSPolicy(pinnedFingerprint: pinnedFingerprint)
        var cookies: [String: String] = [:]
        var target = url
        do {
            for _ in 0..<5 {
                var req = URLRequest(url: target, timeoutInterval: 60)
                req.httpMethod = "POST"
                req.httpBody = body
                req.setValue(contentType, forHTTPHeaderField: "Content-Type")
                req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
                if !cookies.isEmpty { req.setValue(cookies.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; "), forHTTPHeaderField: "Cookie") }
                let out = try await XxdHTTPTransport(policy: policy, followRedirects: false).run(req)
                let r = out.response
                let fields = r.allHeaderFields.reduce(into: [String: String]()) { if let k = $1.key as? String, let v = $1.value as? String { $0[k] = v } }
                for c in HTTPCookie.cookies(withResponseHeaderFields: fields, for: target) { cookies[c.name] = c.value }
                let location = r.value(forHTTPHeaderField: "Location")
                if let location, r.statusCode == 307 || r.statusCode == 308 {
                    guard let next = URL(string: location, relativeTo: target)?.absoluteURL else { return .failure(.network("Bad redirect")) }
                    target = next
                    continue
                }
                // A 301/302/303 would turn the upload into a GET without the picture.
                if location != nil { return .failure(.unexpected("ZenTao did not accept the picture")) }
                return .success(String(decoding: out.data, as: UTF8.self))
            }
            return .failure(.network("Too many redirects"))
        } catch {
            return .failure(xxdMapTransportError(error, policy: policy, fallback: "Picture upload failed"))
        }
    }
}
