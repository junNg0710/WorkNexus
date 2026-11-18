import CoreDomain
import Foundation

/// HTTP seam of the pet catalogue, so the repositories are testable without a network. Not in the Flutter app.
public protocol PetCatalogSource: Sendable {
    /// The raw JSON of one catalogue page.
    func fetchPage(_ query: PetQuery) async throws -> Data
    /// The bytes behind `url` (a sprite sheet, a poster).
    func download(_ url: URL) async throws -> Data
}

/// codex-pets.net, a public catalogue of pets in the Codex pet format (no account needed to browse or download). Only
/// safe-for-work pets are asked for (the API's default `content`). Not in the Flutter app.
public final class CodexPetsHTTP: PetCatalogSource, @unchecked Sendable {
    public static let baseURL = URL(string: "https://codex-pets.net")!
    /// A generic client name: nothing about the user goes out with a request.
    static let userAgent = "WorkNexus-macOS"

    private let session: URLSession
    private let base: URL

    public init(session: URLSession = .shared, base: URL = CodexPetsHTTP.baseURL) {
        self.session = session; self.base = base
    }

    public func fetchPage(_ query: PetQuery) async throws -> Data {
        try await get(Self.pageURL(query, base: base), timeout: 20)
    }

    public func download(_ url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw Failure.validation("Only https downloads are allowed", fields: ["url": url.absoluteString]) }
        return try await get(url, timeout: 120)
    }

    /// `/api/pets?page=&pageSize=&sort=&q=&kind=`.
    static func pageURL(_ query: PetQuery, base: URL) -> URL {
        var c = URLComponents(url: base.appendingPathComponent("api/pets"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "page", value: String(query.page)), URLQueryItem(name: "pageSize", value: String(query.pageSize)),
                     URLQueryItem(name: "sort", value: query.sort.rawValue)]
        if !query.text.isEmpty { items.append(URLQueryItem(name: "q", value: query.text)) }
        if let kind = query.kind { items.append(URLQueryItem(name: "kind", value: kind.rawValue)) }
        c.queryItems = items
        return c.url!
    }

    private func get(_ url: URL, timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.network("codex-pets.net answered \(http.statusCode)")
        }
        return data
    }
}
