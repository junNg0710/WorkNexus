import CoreUI
import SwiftUI

/// The privacy mode's masks. Each reads `\.chatPrivacyHidden` once; turning the mode on or off (or pointing at a reveal
/// region) eases between the real content and the mask with a short opacity change, nothing that lays out again per frame.
/// Ported from: lib/core/widgets/privacy_mask.dart (PrivacyMask, PrivacyFade, PrivacyCover)
/// + lib/features/chat/presentation/widgets/chat_privacy_mask.dart

/// What a hidden name or preview reads as: a fixed run of dots, so not even the length of the real text shows.
let chatPrivacyMaskText = "••••••"

/// How much of a hidden message still shows: enough to see that a message is there and how long it is, too little to read.
let chatPrivacyFadedOpacity = 0.15

/// Shows `mask` in place of `content` while the privacy mode hides `part` (never, when nil), crossfading the two. For
/// content without state of its own: a name, a preview line, a detail.
struct ChatPrivacyMasked<Content: View, Mask: View>: View {
    @Environment(\.chatPrivacyHidden) private var hidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let part: ChatPrivacyPart?
    var alignment: Alignment = .leading
    @ViewBuilder let content: Content
    @ViewBuilder let mask: Mask

    var body: some View {
        let on = part.map(hidden.contains) ?? false
        // Both pinned to the same edge, so the text does not slide while the two widths differ.
        ZStack(alignment: alignment) {
            if on { mask.transition(.opacity) } else { content.transition(.opacity) }
        }
        .animation(ChatPrivacyMotion.ease(reduced: reduceMotion), value: on)
    }
}

/// One line of `text` as the privacy mode shows it: the text, or dots while it hides `part` (never, when nil).
struct ChatPrivacyText: View {
    let text: String
    let part: ChatPrivacyPart?
    let font: Font
    let color: Color

    var body: some View {
        ChatPrivacyMasked(part: part) {
            Text(text).font(font).foregroundStyle(color).lineLimit(1)
        } mask: {
            Text(chatPrivacyMaskText).font(font).foregroundStyle(color).lineLimit(1)
        }
    }
}

extension View {
    /// Fades the view almost out while the privacy mode hides `part` (messages, by default) — for content on a solid
    /// background, a bubble's insides or a card's body. Only the painting changes: a text selection, a playing video and
    /// the layout stay as they are.
    func chatPrivacyFade(_ part: ChatPrivacyPart = .message) -> some View { modifier(ChatPrivacyFade(part: part)) }

    /// `chatPrivacyFade()` only `when` set (stable for a message: whether it is a picture); otherwise the view as it is, with
    /// nothing added to it.
    @ViewBuilder func chatPrivacyFade(when on: Bool) -> some View {
        if on { chatPrivacyFade() } else { self }
    }

    /// Lays an opaque grey box over a picture (an image, a sticker, a video, a big emoji) while the privacy mode hides
    /// messages; the picture stays built under it, so a video keeps playing and an image need not load again.
    func chatPrivacyCover(cornerRadius: CGFloat? = nil) -> some View { modifier(ChatPrivacyCover(cornerRadius: cornerRadius)) }
}

private struct ChatPrivacyFade: ViewModifier {
    @Environment(\.chatPrivacyHidden) private var hidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let part: ChatPrivacyPart

    func body(content: Content) -> some View {
        let on = hidden.contains(part)
        // Only the opacity animates, not whatever else changes in the content at the same moment.
        content.animation(ChatPrivacyMotion.ease(reduced: reduceMotion)) { $0.opacity(on ? chatPrivacyFadedOpacity : 1) }
    }
}

private struct ChatPrivacyCover: ViewModifier {
    @Environment(\.chatPrivacyHidden) private var hidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        let on = hidden.contains(.message)
        content.overlay {
            // Over the picture, so it never moves the picture and loses its state; at rest with the mode off it is nothing.
            ZStack {
                if on { ChatPrivacyCoverFill(cornerRadius: cornerRadius).transition(.opacity) }
            }
            .allowsHitTesting(false)
            .animation(ChatPrivacyMotion.ease(reduced: reduceMotion), value: on)
        }
    }
}

/// The grey a hidden picture shows as. Opaque (the skeleton tints alone are see-through) and a step off the surface, so the
/// box still reads.
struct ChatPrivacyCoverFill: View {
    @Environment(\.appTheme) private var theme
    var cornerRadius: CGFloat?

    var body: some View {
        ZStack { theme.colors.panel2; theme.colors.skel2 }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? theme.radii.md))
    }
}
