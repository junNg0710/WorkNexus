/// Not in the Flutter app.
import Foundation

public extension ChatSticker {
    /// What a recently sent sticker is remembered by: its set and file name, not its path (the app's own stickers move
    /// with the app, so a path kept from an earlier run would no longer name them).
    var recentKey: String { "\(custom ? "c" : "b"):\(pack)/\(name)" }
}

/// The stickers sent lately, newest first: sending one puts it in front (once), and the oldest fall off the end.
public struct RecentStickers: Sendable {
    public static let limit = 24
    public init() {}

    /// `keys` after `sticker` was sent.
    public func adding(_ sticker: ChatSticker, to keys: [String], limit: Int = RecentStickers.limit) -> [String] {
        Array(([sticker.recentKey] + keys.filter { $0 != sticker.recentKey }).prefix(max(limit, 0)))
    }

    /// The stickers `keys` name, in that order; one that is gone (its set was removed) is left out.
    public func resolve(_ keys: [String], in all: [ChatSticker]) -> [ChatSticker] {
        let byKey = Dictionary(all.map { ($0.recentKey, $0) }, uniquingKeysWith: { first, _ in first })
        return keys.compactMap { byKey[$0] }
    }
}
