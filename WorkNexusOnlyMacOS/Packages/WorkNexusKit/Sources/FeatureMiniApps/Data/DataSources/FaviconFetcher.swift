import Foundation

/// Ported from: lib/features/mini_apps/data/datasources/site_icon_source.dart + favicon_fetcher.dart
/// A site's icon image and the file extension to keep it under.
public struct SiteIcon: Sendable, Equatable {
    public var data: Data
    public var fileExtension: String
    public init(data: Data, fileExtension: String) { self.data = data; self.fileExtension = fileExtension }
}

/// Where an app's icon comes from when the user did not pick one: the site itself.
public protocol SiteIconSource: Sendable {
    /// The icon of the page at `page`; nil when the site offers none.
    func fetch(_ page: URL) async -> SiteIcon?
}

/// Finds and downloads a web page's icon: the best `<link rel="…icon…">` the page declares, then `/favicon.ico`. Talks to
/// the site itself only. SVG icons are skipped.
public struct FaviconFetcher: SiteIconSource {
    private let session: URLSession
    private static let maxBytes = 1024 * 1024

    public init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 WorkNexus"]
        self.session = URLSession(configuration: config)
    }

    public func fetch(_ page: URL) async -> SiteIcon? {
        var candidates: [URL] = []
        var origin = page
        if let (data, response) = try? await session.data(from: page) {
            origin = response.url ?? page
            candidates += Self.declaredIcons(in: String(decoding: data, as: UTF8.self), base: origin)
        }
        if var c = URLComponents(url: origin, resolvingAgainstBaseURL: false) {
            c.path = "/favicon.ico"; c.query = nil; c.fragment = nil
            if let u = c.url { candidates.append(u) }
        }
        for url in candidates.prefix(4) { if let icon = await download(url) { return icon } }
        return nil
    }

    /// The icons the page declares, best first: touch icons (large), then the largest sized icon, then the rest.
    static func declaredIcons(in html: String, base: URL) -> [URL] {
        var scored: [(Int, URL)] = []
        for tag in matches(#"<link\b[^>]*>"#, in: html) {
            let attrs = attributes(of: tag)
            let rel = (attrs["rel"] ?? "").lowercased()
            guard rel.contains("icon"), let href = attrs["href"], !href.isEmpty, let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  !url.path.lowercased().hasSuffix(".svg") else { continue }
            let size = Int((attrs["sizes"] ?? "").split(separator: "x").first ?? "")
            scored.append(((rel.contains("apple-touch-icon") ? 1000 : 0) + (size ?? 16), url))
        }
        return scored.enumerated().sorted { a, b in a.element.0 != b.element.0 ? a.element.0 > b.element.0 : a.offset < b.offset }.map(\.element.1)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func attributes(of tag: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let re = try? NSRegularExpression(pattern: #"([a-zA-Z-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#) else { return out }
        for m in re.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let k = Range(m.range(at: 1), in: tag) else { continue }
            for g in 2...4 where m.range(at: g).location != NSNotFound { if let r = Range(m.range(at: g), in: tag) { out[tag[k].lowercased()] = String(tag[r]) } }
        }
        return out
    }

    private func download(_ url: URL) async -> SiteIcon? {
        guard let (data, response) = try? await session.data(from: url), let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        let type = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if data.count < 64 || data.count > Self.maxBytes || type.contains("text/") || type.contains("svg") { return nil }
        return SiteIcon(data: data, fileExtension: Self.fileExtension(url, contentType: type))
    }

    static func fileExtension(_ url: URL, contentType: String) -> String {
        let path = url.path.lowercased()
        for ext in ["png", "jpg", "jpeg", "gif", "webp", "ico"] where path.hasSuffix(".\(ext)") { return ext }
        if contentType.contains("png") { return "png" }
        if contentType.contains("jpeg") { return "jpg" }
        if contentType.contains("webp") { return "webp" }
        return "ico"
    }
}
