/// Ported from: lib/core/navigation/person_chip.dart (consumers of `personAvatarBuilderProvider` / `personChipBuilderProvider`)
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Builds the request the shared `\.personAvatar` / `\.personChip` hooks take.
enum ZentaoPersonRequest {
    static func make(accountId: String, name: String, diameter: CGFloat) -> PersonAvatarRequest? {
        PersonAvatarRequest(accountId: accountId, name: name, diameter: diameter)
    }
}

/// A ZenTao person's avatar at `diameter`, drawn by the host's `\.personAvatar` hook (the chat photo) when one is
/// installed, else an initial-letter avatar.
public struct ZentaoPersonAvatar: View {
    @Environment(\.personAvatar) private var hook
    let accountId: String; let name: String; let diameter: CGFloat
    public init(accountId: String, name: String, diameter: CGFloat = 24) { self.accountId = accountId; self.name = name; self.diameter = diameter }

    public var body: some View {
        if let hook, let req = ZentaoPersonRequest.make(accountId: accountId, name: name, diameter: diameter) {
            hook(req).frame(width: diameter, height: diameter)
        } else {
            UserAvatar(name: name, size: diameter)
        }
    }
}

/// A ZenTao person (avatar + name): the host's `\.personChip` hook (photo, verified check, tap to chat) when installed,
/// else a plain avatar with the name.
public struct ZentaoPersonChip: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.personChip) private var hook
    let accountId: String; let name: String; let avatarSize: CGFloat
    public init(accountId: String, name: String, avatarSize: CGFloat = 24) { self.accountId = accountId; self.name = name; self.avatarSize = avatarSize }

    public var body: some View {
        if let hook, let req = ZentaoPersonRequest.make(accountId: accountId, name: name, diameter: avatarSize) {
            hook(req)
        } else {
            HStack(spacing: theme.spacing.s6) {
                ZentaoPersonAvatar(accountId: accountId, name: name, diameter: avatarSize)
                Text(name).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).lineLimit(1)
            }
        }
    }
}
