import CoreDomain
import Foundation
import ImageIO

/// Authenticated asset bytes (inline images, attachments, stream requests). Ported from zentao_client.dart.
extension ZenTaoClient {
    /// Fetches raw bytes for an (authenticated, self-signed-TLS) asset such as an inline image referenced by a
    /// ticket's rich text - e.g. ZenTao's `file-read-<id>.png`, which 302-redirects to the login page unless the
    /// session is presented. Only an image response is accepted (so a login-page HTML body is never mistaken
    /// for an image).
    func fetchBytes(_ url: String) async throws -> Data? { try await authedBytes(url, imageOnly: true) }

    /// Downloads an attachment's raw bytes through the authenticated session, accepting any content type.
    func downloadBytes(_ url: String) async throws -> Data? { try await authedBytes(url, imageOnly: false) }

    private func resolve(_ url: String) -> (resolved: URL, onServer: Bool)? {
        guard let base = URL(string: "\(baseUrl)/"), let resolved = URL(string: url, relativeTo: base)?.absoluteURL else { return nil }
        return (resolved, resolved.host == base.host)
    }

    private func withSession(_ url: URL, _ token: String) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        var items = (c.queryItems ?? []).filter { $0.name != "zentaosid" }
        items.append(URLQueryItem(name: "zentaosid", value: token))
        c.queryItems = items
        return c.url ?? url
    }

    /// The URL and session headers a player needs to fetch attachment `url` itself - ZenTao takes the session as
    /// a `zentaosid` cookie, header and query param. Nil for a URL off this server (it carries no session).
    func streamRequest(_ url: String) async throws -> MediaRequest? {
        guard let (resolved, onServer) = resolve(url), onServer else { return nil }
        let token = try await ensureToken()
        return MediaRequest(url: withSession(resolved, token), headers: ["Cookie": "zentaosid=\(token)", "Token": token])
    }

    /// Shared transport for `fetchBytes`/`downloadBytes`: attaches the session id as a `zentaosid` cookie
    /// (ZenTao's session mechanism) plus the `Token` header and a query param, and does NOT follow redirects.
    ///
    /// Unlike the v1 channel - where a dead session heals through the re-login on a 401 - the classic asset
    /// channel signals a session problem as a 302 to the login page, which used to be a dead end (the "first
    /// open shows broken images" bug). So a failed on-server fetch recovers in two steps: once more on the SAME
    /// session (right after login ZenTao can bounce the classic channel's first hit while the freshly minted
    /// token warms up), then once on a FRESH login (session truly invalidated; concurrent recoveries share the
    /// one in-flight `/tokens` request). Off-server URLs carry no session, so they get no retry.
    private func authedBytes(_ url: String, imageOnly: Bool) async throws -> Data? {
        guard let (resolved, onServer) = resolve(url) else { return nil }

        var refused = ""
        func attempt(_ token: String) async throws -> Data? {
            var request = ZenTaoRequest(url: onServer ? withSession(resolved, token) : resolved)
            request.followRedirects = false
            request.rawBytes = true
            if onServer { request.headers = ["Cookie": "zentaosid=\(token)", "Token": token] }
            let res = try await perform(request)
            let data = res.data as? Data ?? res.rawData
            // An image is told by its bytes, not only its declared type: ZenTao serves some uploads as
            // `application/octet-stream`, and those showed as broken images. A login page (HTML) is never one.
            if res.status == 200, !data.isEmpty, !imageOnly || res.contentType.lowercased().hasPrefix("image") || Self.isImage(data) { return data }
            refused = "HTTP \(res.status), \(res.contentType.isEmpty ? "no type" : res.contentType), \(data.count) bytes"
            return nil
        }

        let token = try await ensureToken()
        var bytes = try await attempt(token)
        if bytes == nil, onServer { bytes = try await attempt(token) }        // same session, second chance
        if bytes == nil, onServer {
            try await authenticate()                                          // session presumed dead
            bytes = try await attempt(try await ensureToken())
        }
        if bytes == nil {
            // Which asset (its path only: the query carries the session) and how ZenTao answered, to trace a broken image.
            Diagnostics.info("zentao", "\(imageOnly ? "Image" : "File") \(resolved.path) not loaded: \(refused)")
        }
        return bytes
    }

    /// Whether `data` is a picture ImageIO can read (PNG, JPEG, GIF, WebP, HEIC, TIFF, BMP…).
    static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }
}
