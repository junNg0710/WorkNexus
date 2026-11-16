import Foundation

/// Ported from: lib/features/mini_apps/domain/entities/cookie_import.dart
/// That a `site`'s cookies were brought in from `source`: kept, without the cookies themselves, to import them again from
/// the same place and to see whether they are still there. One per site; the latest import wins.
public struct CookieImport: Sendable, Equatable {
    public var site: String
    public var source: CookieSource
    public var importedAt: Date
    /// The cookies whose loss means the sign-in is gone.
    public var keys: [CookieKey]
    public init(site: String, source: CookieSource, importedAt: Date, keys: [CookieKey]) {
        self.site = site; self.source = source; self.importedAt = importedAt; self.keys = keys
    }
}

/// An import and whether its sign-in cookies are still in the web view.
public struct CookieImportState: Sendable, Equatable {
    public var cookieImport: CookieImport
    /// How many of `cookieImport.keys` are gone (expired or removed).
    public var missing: Int
    public init(cookieImport: CookieImport, missing: Int = 0) { self.cookieImport = cookieImport; self.missing = missing }
    public var expired: Bool { missing > 0 }
}
