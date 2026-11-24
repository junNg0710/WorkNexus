/// Not in the Flutter app.
import Foundation

/// The last things searched for on the Chat page, newest first, kept on this Mac per account. Offered again when the
/// search field is clicked before anything is typed.
public struct ChatRecentSearches {
    public static let limit = 6
    private let defaults: UserDefaults
    private let key: String

    public init(accountId: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults; key = "chat.recentSearches.\(accountId)"
    }

    public var all: [String] { defaults.stringArray(forKey: key) ?? [] }

    /// Puts `query` first; the same words searched before (in any case) move up instead of being listed twice.
    public func add(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let rest = all.filter { $0.compare(q, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
        defaults.set(Array(([q] + rest).prefix(Self.limit)), forKey: key)
    }

    public func clear() { defaults.removeObject(forKey: key) }
}
