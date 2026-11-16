import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// OpenGraph / oEmbed parsing of a fetched page.
/// Ported from: lib/features/chat/data/datasources/link_preview_parser.dart
enum LinkPreviewParser {
    private static let metaTag = RX(#"<meta\b[^>]*>"#, caseInsensitive: true)
    private static let titleTag = RX(#"<title[^>]*>([\s\S]*?)</title>"#, caseInsensitive: true)
    private static let attribute = RX(#"([a-zA-Z:_-]+)\s*=\s*("([^"]*)"|'([^']*)')"#)
    private static let numericEntity = RX(#"&#(x?)([0-9a-fA-F]+);"#)

    static func parse(html: String, pageUrl: URL) -> LinkPreview? {
        var meta: [String: String] = [:]
        for tag in metaTag.matches(html) {
            var attrs: [String: String] = [:]
            for m in attribute.matches(tag.whole) { attrs[(m[1] ?? "").lowercased()] = m[3] ?? m[4] ?? "" }
            guard let key = (attrs["property"] ?? attrs["name"])?.lowercased(), let content = attrs["content"],
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if meta[key] == nil { meta[key] = decodeEntities(content.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        let tagTitle = titleTag.first(html)?[1].map { decodeEntities($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let title = meta["og:title"] ?? meta["twitter:title"] ?? tagTitle, !title.isEmpty else { return nil }
        let image = meta["og:image"] ?? meta["twitter:image"]
        return LinkPreview(url: pageUrl.absoluteString, siteName: meta["og:site_name"] ?? pageUrl.host, title: title,
                           description: meta["og:description"] ?? meta["twitter:description"] ?? meta["description"],
                           imageUrl: image.flatMap { URL(string: $0, relativeTo: pageUrl)?.absoluteURL.absoluteString })
    }

    static func parseOEmbed(json: String, url: String) -> LinkPreview? {
        guard let v = try? JSONValue.parse(json), let title = v["title"]?.string else { return nil }
        return LinkPreview(url: url, siteName: v["provider_name"]?.string ?? "YouTube", title: title,
                           description: v["author_name"]?.string, imageUrl: v["thumbnail_url"]?.string)
    }

    static func decodeEntities(_ s: String) -> String {
        numericEntity.replace(s) { m in
            let radix = (m[1] ?? "").isEmpty ? 10 : 16
            guard let n = UInt32(m[2] ?? "", radix: radix), let u = Unicode.Scalar(n) else { return m.whole }
            return String(Character(u))
        }
        .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// Fetches a page (first 512 KB, 8 s) and reads its preview; YouTube goes through oEmbed.
/// Ported from: lib/features/chat/data/datasources/link_preview_http_datasource.dart
struct LinkPreviewHttpDatasource: Sendable {
    static let maxBytes = 512 * 1024
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36 WorkNexus"

    func fetch(_ url: String) async -> Outcome<LinkPreview?> {
        guard let uri = URL(string: url), ["http", "https"].contains(uri.scheme?.lowercased()) else { return .success(nil) }
        do {
            if Self.isYouTube(uri) {
                var c = URLComponents(string: "https://www.youtube.com/oembed")!
                c.queryItems = [URLQueryItem(name: "url", value: url), URLQueryItem(name: "format", value: "json")]
                guard let page = try await read(c.url!, htmlOnly: false) else { return .success(nil) }
                return .success(LinkPreviewParser.parseOEmbed(json: page.text, url: url))
            }
            guard let page = try await read(uri, htmlOnly: true) else { return .success(nil) }
            return .success(LinkPreviewParser.parse(html: page.text, pageUrl: page.url))
        } catch let e as URLError where e.code == .timedOut { return .failure(.network("Link preview timed out")) }
        catch { return .failure(.network("Link preview failed: \(error.localizedDescription)")) }
    }

    private func read(_ url: URL, htmlOnly: Bool) async throws -> (text: String, url: URL)? {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("text/html,application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        if htmlOnly, !(http.mimeType ?? "").contains("html") { return nil }
        var data = Data()
        for try await b in bytes { data.append(b); if data.count >= Self.maxBytes { break } }
        return (String(decoding: data, as: UTF8.self), http.url ?? url)
    }

    static func isYouTube(_ u: URL) -> Bool {
        let h = (u.host ?? "").lowercased()
        return h == "youtu.be" || h == "youtube.com" || h.hasSuffix(".youtube.com")
    }
}

/// Preview cache: memory, then the `chatLinkPreviews` table (fresh for 7 days, kept 30, "no preview" is cached too).
/// Ported from: lib/features/chat/data/repositories/cached_link_preview_repository.dart (+ link_preview_local_datasource)
public final class CachedLinkPreviewRepository: LinkPreviewRepository, @unchecked Sendable {
    static let maxAge: TimeInterval = 7 * 86400
    static let keepFor: TimeInterval = 30 * 86400
    private static let maxInMemory = 300

    private let db: AppDatabase
    private let http: LinkPreviewHttpDatasource
    private let now: @Sendable () -> Date
    private let memory = Locked<[(url: String, task: Task<Outcome<LinkPreview?>, Never>)]>([])

    public init(db: AppDatabase, now: @escaping @Sendable () -> Date = Date.init) {
        self.db = db; http = LinkPreviewHttpDatasource(); self.now = now
    }

    init(db: AppDatabase, http: LinkPreviewHttpDatasource, now: @escaping @Sendable () -> Date) { self.db = db; self.http = http; self.now = now }

    public func preview(url: String) async -> Outcome<LinkPreview?> {
        let task: Task<Outcome<LinkPreview?>, Never> = memory.with { m in
            if let i = m.firstIndex(where: { $0.url == url }) { let hit = m.remove(at: i); m.append(hit); return hit.task }
            if m.count >= Self.maxInMemory { m.removeFirst() }
            let t = Task { await self.load(url) }
            m.append((url, t))
            return t
        }
        let result = await task.value
        if case .failure = result { memory.with { m in m.removeAll { $0.url == url } } }
        return result
    }

    private func load(_ url: String) async -> Outcome<LinkPreview?> {
        let stored = try? await db.writer.read { d in try Row.fetchOne(d, sql: "SELECT * FROM chatLinkPreviews WHERE url=?", arguments: [url]) }
        let storedPreview: (preview: LinkPreview?, fetchedAt: Date)? = stored.map { r in
            let empty: Bool = r["empty"]
            return (empty ? nil : LinkPreview(url: r["pageUrl"] ?? url, siteName: r["siteName"], title: r["title"], description: r["description"], imageUrl: r["imageUrl"]), r["fetchedAt"])
        }
        if let s = storedPreview, now().timeIntervalSince(s.fetchedAt) < Self.maxAge { return .success(s.preview) }
        let fetched = await http.fetch(url)
        switch fetched {
        case .success(let value): await store(url, value); return fetched
        case .failure: return storedPreview.map { .success($0.preview) } ?? fetched
        }
    }

    private func store(_ url: String, _ p: LinkPreview?) async {
        let at = now()
        // Still shown from memory; it is just fetched again next launch.
        try? await db.writer.write { d in
            try d.execute(sql: "INSERT INTO chatLinkPreviews (url,empty,pageUrl,siteName,title,description,imageUrl,fetchedAt) VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(url) DO UPDATE SET empty=excluded.empty, pageUrl=excluded.pageUrl, siteName=excluded.siteName, title=excluded.title, description=excluded.description, imageUrl=excluded.imageUrl, fetchedAt=excluded.fetchedAt",
                          arguments: [url, p == nil, p?.url, p?.siteName, p?.title, p?.description, p?.imageUrl, at])
            try d.execute(sql: "DELETE FROM chatLinkPreviews WHERE fetchedAt<?", arguments: [at.addingTimeInterval(-Self.keepFor)])
        }
    }
}

/// Ported from: lib/features/chat/data/repositories/local_message_translation_repository.dart
final class LocalMessageTranslationRepository: MessageTranslationRepository, @unchecked Sendable {
    private let local: ChatLocalDatasource
    init(local: ChatLocalDatasource) { self.local = local }

    func find(accountId: String, gid: String, targetLang: String) async -> Outcome<ChatMessageTranslation?> {
        do { return .success(try await local.messageTranslation(accountId, gid, targetLang)) }
        catch { return .failure(.storage("Could not read the translation: \(error.localizedDescription)")) }
    }
    func watch(accountId: String, gid: String, targetLang: String) -> AsyncStream<ChatMessageTranslation?> { local.watchMessageTranslation(accountId, gid, targetLang) }
    func setVisible(accountId: String, gid: String, targetLang: String, visible: Bool) async -> Outcome<Void> {
        do { try await local.setMessageTranslationVisible(accountId, gid, targetLang, visible: visible); return .success(()) }
        catch { return .failure(.storage("Could not save the translation: \(error.localizedDescription)")) }
    }
    func save(_ t: ChatMessageTranslation) async -> Outcome<Void> {
        do { try await local.saveMessageTranslation(t); return .success(()) }
        catch { return .failure(.storage("Could not save the translation: \(error.localizedDescription)")) }
    }
}
