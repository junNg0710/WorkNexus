import Foundation

/// Ported from: lib/features/mini_apps/data/datasources/browser_cookies/safari_cookie_reader.dart
/// Safari's cookies, kept in its own binary file inside its container. macOS lets an app read it only with Full Disk
/// Access: without it, reading throws a refused-permission error.
struct SafariCookieReader: Sendable {
    private let home: String
    init(home: String? = nil) { self.home = home ?? ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory() }

    /// Whether Safari is here at all. Its cookie file cannot be looked at without access, so this does not say whether it can be read.
    var installed: Bool { FileManager.default.fileExists(atPath: "/Applications/Safari.app") }

    private var candidates: [String] {
        ["\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies", "\(home)/Library/Cookies/Cookies.binarycookies"]
    }

    func read() async throws -> [BrowserCookie] {
        var refused: Error?
        for path in candidates {
            do { return try BinaryCookies.parse(try Data(contentsOf: URL(fileURLWithPath: path))) }
            catch let e as BinaryCookies.FormatError { throw e }
            catch { refused = refused ?? error }
        }
        throw refused ?? CocoaError(.fileNoSuchFile)
    }
}

/// Reads a `Cookies.binarycookies` file: a big-endian page table, then pages of little-endian cookie records whose strings
/// sit at offsets inside them. Throws `FormatError` on a file that is not one.
enum BinaryCookies {
    struct FormatError: Error { let message: String }
    /// Seconds between 1970 and 2001, where Apple's dates start.
    private static let appleEpoch = 978_307_200.0

    static func parse(_ bytes: Data) throws -> [BrowserCookie] {
        let b = [UInt8](bytes)
        guard b.count >= 8, String(bytes: b[0..<4], encoding: .ascii) == "cook" else { throw FormatError(message: "Not a binary cookies file") }
        func be32(_ at: Int) throws -> Int {
            guard at >= 0, at + 4 <= b.count else { throw FormatError(message: "Truncated") }
            return Int(b[at]) << 24 | Int(b[at + 1]) << 16 | Int(b[at + 2]) << 8 | Int(b[at + 3])
        }
        let pages = try be32(4)
        var pageStart = 8 + pages * 4
        var cookies: [BrowserCookie] = []
        for i in 0..<pages {
            let size = try be32(8 + i * 4)
            let count = try le32(b, pageStart + 4)
            for c in 0..<count { cookies.append(try cookie(b, at: pageStart + (try le32(b, pageStart + 8 + c * 4)))) }
            pageStart += size
        }
        return cookies
    }

    private static func le32(_ b: [UInt8], _ at: Int) throws -> Int {
        guard at >= 0, at + 4 <= b.count else { throw FormatError(message: "Truncated") }
        return Int(b[at]) | Int(b[at + 1]) << 8 | Int(b[at + 2]) << 16 | Int(b[at + 3]) << 24
    }

    private static func cookie(_ b: [UInt8], at: Int) throws -> BrowserCookie {
        func text(_ offset: Int) throws -> String {
            let start = at + (try le32(b, at + offset))
            guard start >= 0, start <= b.count else { throw FormatError(message: "Truncated") }
            var end = start
            while end < b.count, b[end] != 0 { end += 1 }
            return String(decoding: b[start..<end], as: UTF8.self)
        }
        let flags = try le32(b, at + 8)
        guard at + 48 <= b.count else { throw FormatError(message: "Truncated") }
        var bits: UInt64 = 0
        for k in 0..<8 { bits |= UInt64(b[at + 40 + k]) << (8 * UInt64(k)) }
        let expiry = Double(bitPattern: bits)
        return BrowserCookie(name: try text(20), value: try text(28), domain: try text(16), path: try text(24),
                             expires: expiry <= 0 ? nil : Date(timeIntervalSince1970: expiry + appleEpoch),
                             secure: flags & 1 != 0, httpOnly: flags & 4 != 0)
    }
}
