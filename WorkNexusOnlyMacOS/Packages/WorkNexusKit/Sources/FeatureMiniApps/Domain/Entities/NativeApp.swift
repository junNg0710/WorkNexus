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
    /// The name the user gave it on the rail; nil keeps the app's own (`name`).
    public var customName: String?
    /// An image the user picked for it on the rail (a copy kept with the app's data); nil shows the app's own icon.
    public var iconPath: String?

    public init(id: String, name: String, bundleId: String, path: String, position: Int, customName: String? = nil, iconPath: String? = nil) {
        self.id = id; self.name = name; self.bundleId = bundleId; self.path = path; self.position = position
        self.customName = customName; self.iconPath = iconPath
    }

    /// What the rail and the menus call it: the user's name for it, else the app's own.
    public var label: String {
        let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? name : custom
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
