/// Ported from: lib/features/chat/presentation/widgets/chat_style_specs.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Layout metrics and colours of each `ChatAppearance`, modelled on the real apps (Telegram from its open-source
/// palette and styles). The metrics are the style's design values, like the palettes.
func chatStyleSpec(_ appearance: ChatAppearance, theme: AppTheme, dark: Bool) -> ChatStyle {
    switch appearance {
    case .worknexus:
        return ChatStyle(
            palette: .fromTheme(theme.colors), avatar: .firstOfRun, avatarShape: .circle, avatarSize: 32, ownAvatar: false,
            avatarInDirectChats: true, name: .aboveBubble, time: .belowContent, quote: .inside, separator: .hairline,
            separatorGap: nil, radius: theme.radii.lg, joinRadius: theme.radii.xs, tail: nil,
            padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12), maxWidth: 560, runGap: 2, groupGap: 16,
            fontSize: 13, ticks: false)
    case .telegram:
        return ChatStyle(
            palette: dark ? .telegramNight : .telegramDay, avatar: .lastOfRun, avatarShape: .circle, avatarSize: 33,
            ownAvatar: false, avatarInDirectChats: false, name: .insideBubble, time: .insideEnd, quote: .inside,
            separator: .pill, separatorGap: nil, radius: 16, joinRadius: 6, tail: .curlBottom,
            padding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12), maxWidth: 480, runGap: 3, groupGap: 10,
            fontSize: 14, ticks: true, labelSize: 14, metaSize: 12.5, threadInMeta: true, quoteInSenderColor: true)
    case .zalo:
        return ChatStyle(
            palette: dark ? .zaloDark : .zaloLight, avatar: .firstOfRun, avatarShape: .circle, avatarSize: 40,
            ownAvatar: false, avatarInDirectChats: true, name: .insideBubble, time: .belowContent, quote: .inside,
            separator: .pill, separatorGap: nil, radius: 8, joinRadius: 8, tail: nil,
            padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12), maxWidth: 600, runGap: 4, groupGap: 14,
            fontSize: 14.5, ticks: false)
    case .zentao:
        return ChatStyle(
            palette: dark ? .zentaoDark : .zentaoLight, avatar: .firstOfRun, avatarShape: .circle, avatarSize: 30,
            ownAvatar: true, avatarInDirectChats: true, name: .header, time: .header, quote: .inside, separator: .plain,
            separatorGap: nil, radius: 4, joinRadius: 4, tail: nil,
            padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10), maxWidth: 560, runGap: 6, groupGap: 16,
            fontSize: 14, ticks: false, ownOnLeft: true)
    case .wechat:
        return ChatStyle(
            palette: dark ? .wechatDark : .wechatLight, avatar: .everyMessage, avatarShape: .roundedSquare, avatarSize: 36,
            ownAvatar: true, avatarInDirectChats: true, name: .aboveBubble, time: .separators, quote: .below,
            separator: .plain, separatorGap: 5 * 60, radius: 4, joinRadius: 4, tail: .triangleTop,
            padding: EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12), maxWidth: 520, runGap: 16, groupGap: 16,
            fontSize: 14, ticks: false)
    case .tbchat:
        return ChatStyle(
            palette: dark ? .tbchatDark : .tbchatLight, avatar: .firstOfRun, avatarShape: .circle, avatarSize: 40,
            ownAvatar: false, avatarInDirectChats: false, name: .aboveRow, time: .insideAligned, quote: .inside,
            separator: .pill, separatorGap: nil, radius: 12, joinRadius: 12,
            // TBChat points a small triangle near the top at the avatar, with every corner rounded (not Telegram's
            // curl at the bottom).
            tail: .triangleTop, padding: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16), maxWidth: 560,
            runGap: 4, groupGap: 16, fontSize: 15, ticks: false)
    }
}
