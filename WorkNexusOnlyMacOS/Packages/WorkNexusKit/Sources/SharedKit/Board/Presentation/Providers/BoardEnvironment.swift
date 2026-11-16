import CoreDomain
import SwiftUI

/// Injection points the shared board / detail views use for things only a feature or tool knows (rule 10.1: shared
/// code never imports them). The composition root or a tool module sets these on the view tree.
public struct PersonAvatarRequest: Sendable {
    public var accountId: String; public var name: String; public var diameter: CGFloat
    public init(accountId: String, name: String, diameter: CGFloat) { self.accountId = accountId; self.name = name; self.diameter = diameter }
}

private struct TicketCardAccessoryKey: EnvironmentKey { static let defaultValue: ((Ticket) -> AnyView)? = nil }
private struct PersonAvatarKey: EnvironmentKey { static let defaultValue: ((PersonAvatarRequest) -> AnyView)? = nil }
private struct PersonChipKey: EnvironmentKey { static let defaultValue: ((PersonAvatarRequest) -> AnyView)? = nil }

public extension EnvironmentValues {
    /// A small trailing accessory on every board card (the translation-state dot from FeatureTranslation).
    var ticketCardAccessory: ((Ticket) -> AnyView)? {
        get { self[TicketCardAccessoryKey.self] } set { self[TicketCardAccessoryKey.self] = newValue }
    }
    /// A person's avatar in card / table assignee chips (ZenTao avatars need the account's authenticated client).
    var personAvatar: ((PersonAvatarRequest) -> AnyView)? {
        get { self[PersonAvatarKey.self] } set { self[PersonAvatarKey.self] = newValue }
    }
    /// A person's full chip (avatar + name) in the detail header's "assigned to / opened by" fields.
    var personChip: ((PersonAvatarRequest) -> AnyView)? {
        get { self[PersonChipKey.self] } set { self[PersonChipKey.self] = newValue }
    }
}
