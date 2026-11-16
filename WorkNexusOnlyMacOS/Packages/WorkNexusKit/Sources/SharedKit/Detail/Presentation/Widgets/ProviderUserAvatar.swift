import AppKit
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/provider_user_avatar.dart
/// A person's avatar fetched through an authenticated loader (initial on the accent tint until it arrives), with
/// an optional name beside it (`ProviderUserAvatar`).
public typealias AvatarLoader = @Sendable (String) async -> Data?

public struct ProviderAvatarImage: View {
    @Environment(\.appTheme) private var theme
    let name: String; let avatarUrl: String?; let imageLoader: AvatarLoader; var diameter: CGFloat
    @State private var image: NSImage?

    public init(name: String, avatarUrl: String?, imageLoader: @escaping AvatarLoader, diameter: CGFloat = 24) {
        self.name = name; self.avatarUrl = avatarUrl; self.imageLoader = imageLoader; self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            theme.colors.sel
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else {
                Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
                    .font(theme.typography.metaStrong).foregroundStyle(theme.colors.accent)
            }
        }
        .frame(width: diameter, height: diameter).clipShape(Circle())
        .task(id: avatarUrl) {
            guard let url = avatarUrl, !url.isEmpty, let data = await imageLoader(url), !data.isEmpty else { image = nil; return }
            image = NSImage(data: data)
        }
    }
}

public struct ProviderUserAvatar<Trailing: View>: View {
    @Environment(\.appTheme) private var theme
    let name: String; let avatarUrl: String?; let imageLoader: AvatarLoader; let trailing: Trailing

    public init(name: String, avatarUrl: String?, imageLoader: @escaping AvatarLoader, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.name = name; self.avatarUrl = avatarUrl; self.imageLoader = imageLoader; self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: theme.spacing.s6) {
            ProviderAvatarImage(name: name, avatarUrl: avatarUrl, imageLoader: imageLoader)
            Text(name).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }
}
