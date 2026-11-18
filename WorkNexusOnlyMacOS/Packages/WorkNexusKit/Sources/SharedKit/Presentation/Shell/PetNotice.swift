import Foundation

/// Something waiting for the user, as the pet says it: what it says, and what a click on it opens (`ShellHost.petOpen`).
/// Not in the Flutter app.
public struct PetNotice: Equatable, Sendable {
    public var text: String
    public var link: String?
    public init(text: String, link: String?) { self.text = text; self.link = link }
}
