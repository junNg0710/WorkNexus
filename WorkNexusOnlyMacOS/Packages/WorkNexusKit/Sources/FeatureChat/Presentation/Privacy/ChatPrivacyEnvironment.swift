import CoreUI
import SwiftUI

/// What the privacy mode hides, as the chat views see it: one environment value, read once per view, so scrolling a list
/// never asks anything about it. Inside a reveal region the pointer is on, nothing is hidden.
/// Ported from: lib/features/chat/presentation/providers/chat_privacy_providers.dart (`chatPrivacyHiddenProvider`)
/// + lib/core/widgets/privacy_mask.dart (`PrivacyRevealRegion`)
private struct ChatPrivacyHiddenKey: EnvironmentKey { static let defaultValue: Set<ChatPrivacyPart> = [] }

extension EnvironmentValues {
    /// The parts of the chat hidden here: what the settings hide, or nothing inside a reveal region under the pointer.
    var chatPrivacyHidden: Set<ChatPrivacyPart> {
        get { self[ChatPrivacyHiddenKey.self] }
        set { self[ChatPrivacyHiddenKey.self] = newValue }
    }
}

extension View {
    /// Sets `\.chatPrivacyHidden` from `\.chatSettings` for the whole chat (the shell).
    func chatPrivacyRoot() -> some View { modifier(ChatPrivacyRoot()) }

    /// An area whose masks all show the real content together while the pointer is over it: the open chat above the input,
    /// a side panel. Pointing anywhere on it shows all of it; the input below is outside it, so typing reveals nothing.
    func chatPrivacyRevealRegion() -> some View { modifier(ChatPrivacyRevealRegion()) }

    /// A chat-list row as its own reveal region, tracking the pointer only while something is hidden: with the mode off a
    /// row adds no hover handling at all.
    func chatPrivacyRowReveal() -> some View { modifier(ChatPrivacyRowReveal()) }
}

private struct ChatPrivacyRoot: ViewModifier {
    @Environment(\.chatSettings) private var settings

    func body(content: Content) -> some View {
        content.environment(\.chatPrivacyHidden, ShouldHideChatPart().hiddenParts(settings.privacy))
    }
}

private struct ChatPrivacyRevealRegion: ViewModifier {
    @Environment(\.chatPrivacyHidden) private var hidden
    @State private var hovered = false

    func body(content: Content) -> some View {
        // One hover handler for the whole area: entering or leaving it redraws the masks inside once, never per scroll frame.
        content
            .environment(\.chatPrivacyHidden, hovered ? [] : hidden)
            .onHover { on in if hovered != on { hovered = on } }
    }
}

private struct ChatPrivacyRowReveal: ViewModifier {
    @Environment(\.chatPrivacyHidden) private var hidden

    @ViewBuilder func body(content: Content) -> some View {
        if hidden.isEmpty { content } else { content.modifier(ChatPrivacyRevealRegion()) }
    }
}

/// The privacy masks' ease (`AppMotion.base`), or none when the system asks for less motion.
enum ChatPrivacyMotion {
    static func ease(reduced: Bool) -> Animation? { reduced ? nil : .easeOut(duration: AppMotion().base) }
}
