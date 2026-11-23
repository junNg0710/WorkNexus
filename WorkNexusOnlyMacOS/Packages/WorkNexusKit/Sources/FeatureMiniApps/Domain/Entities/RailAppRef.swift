/// Not in the Flutter app. One of the things the user added to the rail - a website (mini app) or a Mac app - named without
/// saying where it is kept. The rail keeps them all in one order, whatever their kind.
public struct RailAppRef: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case miniApp = "miniapp"
        case nativeApp = "macapp"
    }

    public var kind: Kind
    /// `MiniApp.id` or `NativeApp.id`.
    public var appId: String

    public init(_ kind: Kind, _ appId: String) { self.kind = kind; self.appId = appId }

    public static func miniApp(_ id: String) -> RailAppRef { RailAppRef(.miniApp, id) }
    public static func nativeApp(_ id: String) -> RailAppRef { RailAppRef(.nativeApp, id) }

    /// `miniapp:<id>` / `macapp:<id>`: the id of its place on the rail, which the keys chosen for it are kept by, and what
    /// a drag of its button carries.
    public var id: String { "\(kind.rawValue):\(appId)" }

    /// The reverse of `id`; nil for anything else (some other text dragged onto the rail).
    public init?(placeId: String) {
        guard let colon = placeId.firstIndex(of: ":"), let kind = Kind(rawValue: String(placeId[..<colon])) else { return nil }
        let appId = String(placeId[placeId.index(after: colon)...])
        guard !appId.isEmpty else { return nil }
        self.init(kind, appId)
    }
}
