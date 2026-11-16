/// New feature, no Dart counterpart. A Mac app (Slack.app, Xcode.app…) the user put on the rail: a click opens it, or brings it forward.
public struct NativeApp: Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    /// What the rail labels it with, as read from the app's `Info.plist` when it was added.
    public var name: String
    /// `CFBundleIdentifier`: tells the same app apart wherever it is installed, and finds it among the running ones.
    public var bundleId: String
    /// Where the `.app` bundle was when it was added (or last located).
    public var path: String
    /// Order on the rail, first to last.
    public var position: Int

    public init(id: String, name: String, bundleId: String, path: String, position: Int) {
        self.id = id; self.name = name; self.bundleId = bundleId; self.path = path; self.position = position
    }
}

/// What an `.app` bundle says about itself.
public struct AppBundleInfo: Sendable, Equatable, Hashable {
    public var name: String
    public var bundleId: String
    public var path: String
    /// A background-only app or menu-bar agent (`LSBackgroundOnly` / `LSUIElement`): it has nothing to open from the rail,
    /// so the installed-apps list leaves it out.
    public var isBackground: Bool

    public init(name: String, bundleId: String, path: String, isBackground: Bool = false) {
        self.name = name; self.bundleId = bundleId; self.path = path; self.isBackground = isBackground
    }
}
