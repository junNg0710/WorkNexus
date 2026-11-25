/// Ported from: lib/core/widgets/app_entrance.dart + message_list_item.dart (a message arriving while the chat is open)
import CoreUI
import Foundation
import SwiftUI

/// The messages that arrived while the chat was open (not the first page, not older or newer pages), each for a moment:
/// a row built within `window` of its message's arrival eases in; one built later — scrolled back into view, or a page
/// loaded — shows as it is. A plain reference, so noting an arrival redraws nothing.
final class ChatArrivals {
    private var at: [String: Date] = [:]
    /// How long after its arrival a row still eases in when it is first built.
    static let window: TimeInterval = 1

    func note(_ gids: some Sequence<String>, at now: Date = Date()) {
        at = at.filter { now.timeIntervalSince($0.value) < Self.window }
        for gid in gids { at[gid] = now }
    }

    /// Whether the row of `gid`, built `now` (default: the current time, read only for a message that did arrive), should
    /// ease in.
    func isFresh(_ gid: String, now: Date? = nil) -> Bool {
        guard let arrived = at[gid] else { return false }
        return (now ?? Date()).timeIntervalSince(arrived) < Self.window
    }
}

/// Eases a row in once, when it is first built: it fades in and rises `rise` points into place (`AppMotion.base`). Decided
/// once - later redraws of the row never play it again - and skipped when the system asks for less motion. At rest it is
/// an opacity of 1 and no offset, which add nothing.
///
/// Not ported: the Flutter row also opened from no height, so the ones above glide up. Here that would lay the lazy list
/// out again on every frame of it; the row keeps its height and only moves within it.
struct ChatRowEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool

    let rise: CGFloat

    init(fresh: Bool, rise: CGFloat) {
        _shown = State(initialValue: !fresh)
        self.rise = rise
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : rise)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: AppMotion().base)) { shown = true } }
            }
    }
}
