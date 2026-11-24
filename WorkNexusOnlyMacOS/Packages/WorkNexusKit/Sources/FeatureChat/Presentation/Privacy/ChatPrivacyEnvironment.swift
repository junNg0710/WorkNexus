import CoreUI
import SwiftUI

/// What the privacy mode hides, as the chat views see it: one environment value, read once per view, so scrolling a list
/// never asks anything about it. Inside a reveal region the pointer is on, nothing is hidden.
/// Ported from: lib/features/chat/presentation/providers/chat_privacy_providers.dart (`chatPrivacyHiddenProvider`)
/// + lib/core/widgets/privacy_mask.dart (`PrivacyRevealRegion`)
private struct ChatPrivacyHiddenKey: EnvironmentKey { static let defaultValue: Set<ChatPrivacyPart> = [] }

private struct ChatPrivacyInUseKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Whether the privacy mode hides anything at all (by the settings, whatever the pointer reveals right now). While
    /// it does not, the masks add nothing to the views they are on - a fade and its animation on every name, quote and
    /// bubble of every row was paid by everyone for a mode few have on.
    var chatPrivacyInUse: Bool {
        get { self[ChatPrivacyInUseKey.self] }
        set { self[ChatPrivacyInUseKey.self] = newValue }
    }

    /// The parts of the chat hidden here: what the settings hide, or nothing inside a reveal region under the pointer.
    var chatPrivacyHidden: Set<ChatPrivacyPart> {
        get { self[ChatPrivacyHiddenKey.self] }
        set { self[ChatPrivacyHiddenKey.self] = newValue }
    }
}

extension View {
    /// Sets `\.chatPrivacyHidden` from `\.chatSettings` for the whole chat (the shell).
    func chatPrivacyRoot() -> some View { modifier(ChatPrivacyRoot()) }

    /// Hides `parts` in this view: the two values the masks read, always set together.
    func chatPrivacy(hiding parts: Set<ChatPrivacyPart>) -> some View {
        environment(\.chatPrivacyHidden, parts).environment(\.chatPrivacyInUse, !parts.isEmpty)
    }

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
        content.chatPrivacy(hiding: ShouldHideChatPart().hiddenParts(settings.privacy))
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
