/// Ported from: lib/features/chat/presentation/widgets/message_bubble.dart (the layout decisions of MessageBubble.build)
import CoreDomain
import Foundation

/// How one message is laid out in its chat style: where its name, avatar, time and tail go. Pure, so the decisions are
/// testable without a view.
struct BubbleLayout: Equatable {
    var mine: Bool
    var alignEnd: Bool
    /// A header names every run, own and in one-to-one chats too.
    var headed: Bool
    var showName: Bool
    /// The name goes over the avatar and bubble together (TBChat).
    var nameOverRow: Bool
    /// The name goes above the bubble, outside it.
    var nameAbove: Bool
    var showFooter: Bool
    var hasQuote: Bool
    /// Drawn bare — an image, a large emoji or a video — rather than inside a bubble.
    var media: Bool
    var hasAvatarSlot: Bool
    var avatarVisible: Bool
    /// Nothing over the bubble: a top tail points at the avatar's centre.
    var avatarLevel: Bool
    /// The tail belongs to the bubble that touches the avatar side.
    var tailed: Bool

    /// Widest an image or video is shown inline.
    static let maxMediaWidth: CGFloat = 360
    /// How much wider than the style's bubble cap a code / Markdown message may grow, so code lines and tables wrap less.
    static let wideBubbleFactor: CGFloat = 1.5

    init(style: ChatStyle, message: ChatMessage, firstOfRun: Bool, lastOfRun: Bool, showSender: Bool, showQuote: Bool = true) {
        mine = message.isMine
        alignEnd = style.alignEnd(mine: mine)
        headed = style.name == .header
        showName = firstOfRun && (headed || (!mine && showSender))
        nameOverRow = showName && style.name == .aboveRow
        hasQuote = showQuote && message.replyToId != nil && !message.deleted
        showFooter = switch style.time {
        case _ where message.sendState != .sent: true
        case .belowContent: lastOfRun
        case .insideEnd, .insideAligned: true
        case .separators, .header: false
        }
        media = chatShowsAsMedia(message) && !hasQuote
        hasAvatarSlot = (!mine || style.ownAvatar) && (showSender || style.avatarInDirectChats)
        avatarVisible = switch style.avatar {
        case .firstOfRun: firstOfRun
        case .lastOfRun: lastOfRun
        case .everyMessage: true
        }
        // Media has no bubble to hold the name, so it goes above it in every style.
        nameAbove = showName && !nameOverRow && (style.name != .insideBubble || media)
        avatarLevel = hasAvatarSlot && avatarVisible && !nameAbove && !(style.quote == .above && hasQuote)
        tailed = style.tail != nil && !media && {
            switch style.tail! {
            case .curlBottom: lastOfRun
            // At the top: beside the avatar — on every message (WeChat) or the run's first (TBChat).
            case .triangleTop: style.avatar == .everyMessage || firstOfRun
            }
        }()
    }

    /// Styles with tails keep the tail's width free on every message, tailed or not, so bubbles, media, quotes and what's
    /// under share one edge.
    func gutter(style: ChatStyle) -> (leading: CGFloat, trailing: CGFloat) {
        guard style.tail != nil else { return (0, 0) }
        return (alignEnd ? 0 : BubbleTail.width, alignEnd ? BubbleTail.width : 0)
    }

    /// Where a top tail points below the bubble's top: the avatar's centre.
    func tailTip(style: ChatStyle) -> CGFloat? { avatarLevel ? style.avatarSize / 2 : nil }
}
