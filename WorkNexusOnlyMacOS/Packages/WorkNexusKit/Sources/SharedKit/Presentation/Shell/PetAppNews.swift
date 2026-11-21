/// Not in the Flutter app.

/// News from an app on the rail (a Mac app's Dock badge going up, a web mini app's notification), for the pet to say.
/// A click on the pet's line opens that app (`link`).
public struct PetAppNews: Equatable, Sendable {
    /// The app's name as the rail shows it.
    public var app: String
    /// What its Dock badge now says ("3"), for a Mac app.
    public var badge: String?
    /// The notification's title and text, for a web mini app (said only with the pet's details on).
    public var title: String?
    public var body: String?
    /// What a click on the pet's line opens (`nativeapp:<id>` / `miniapp:<id>`).
    public var link: String?
    /// Goes up with every piece of news, so the same news twice is said twice.
    public var number: Int

    public init(app: String, badge: String? = nil, title: String? = nil, body: String? = nil, link: String?, number: Int) {
        self.app = app; self.badge = badge; self.title = title; self.body = body; self.link = link; self.number = number
    }
}
