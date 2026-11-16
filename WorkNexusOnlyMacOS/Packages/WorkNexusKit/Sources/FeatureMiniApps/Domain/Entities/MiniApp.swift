/// Ported from: lib/features/mini_apps/domain/entities/mini_app.dart
/// A web page the user added to the rail, opened inside the app.
public struct MiniApp: Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    /// Absolute `http` / `https` address, as normalised by `NormalizeMiniAppUrl`.
    public var url: String
    /// The icon's image file on this device; nil shows the name's initial.
    public var iconPath: String?
    /// The page the app was last on, reopened next time; nil opens `url`.
    public var lastUrl: String?
    /// Order on the rail, first to last.
    public var position: Int

    public init(id: String, name: String, url: String, iconPath: String? = nil, lastUrl: String? = nil, position: Int) {
        self.id = id; self.name = name; self.url = url; self.iconPath = iconPath; self.lastUrl = lastUrl; self.position = position
    }
}
