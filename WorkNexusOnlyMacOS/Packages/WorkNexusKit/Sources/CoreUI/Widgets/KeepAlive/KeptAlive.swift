import AppKit
import SwiftUI

/// Views kept mounted one over the other with only `shown` on screen: the shell's places, the chats last opened. Each
/// view of `content` is marked with `keptAlive(_:active:presence:front:)`, its presence taken from the `KeepAliveWake`
/// the content is given.
///
/// A view off screen is invisible and takes no clicks; what must stop while it is off screen — a shortcut, an endless
/// animation, a refresh timer — reads `@KeptAwake`. That is one object per kept view, handed down once: a switch tells
/// the few views that read it, where a value in the environment (or `disabled`) walked the whole tree of the view going
/// to sleep and of the one waking, a third of what a switch cost.
public struct KeptAlive<Content: View>: View {
    private let shown: String?
    private let keys: [String]
    private let content: (KeepAliveWake) -> Content
    @Environment(KeepAlivePresence.self) private var around: KeepAlivePresence?
    @State private var wake = KeepAliveWake()

    /// `keys`: the views kept now (the presence of one that is gone is forgotten).
    public init(shown: String?, keys: [String], @ViewBuilder content: @escaping (KeepAliveWake) -> Content) {
        self.shown = shown
        self.keys = keys
        self.content = content
    }

    public var body: some View {
        wake.prepare(shown: shown, keys: keys, around: around)
        let wake = wake
        return KeepAliveLayout { content(wake) }
            .onChange(of: shown) { _, key in
                wake.show(key)
                KeptFocus.leaveTextField()
            }
    }
}

public extension View {
    /// One view of a `KeptAlive` stack: off screen (`active` false) it is invisible, takes no clicks and is left out of
    /// accessibility. `front` puts it over the others. `presence` (`KeepAliveWake.presence`) is what `@KeptAwake` reads
    /// inside it.
    func keptAlive(_ key: String, active: Bool, presence: KeepAlivePresence, front: Bool) -> some View {
        environment(presence)
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
            .zIndex(front ? 1 : 0)
            .keepAlivePlace(key, active: active)
    }

    /// `keyboardShortcut` for a control inside a view that may be kept alive off screen: the shortcut is its only while
    /// that view is on screen (a control off screen would answer it too — it is still there).
    func keptShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        modifier(KeptShortcut(shortcut: KeyboardShortcut(key, modifiers: modifiers)))
    }

    func keptShortcut(_ shortcut: KeyboardShortcut) -> some View { modifier(KeptShortcut(shortcut: shortcut)) }
}

private struct KeptShortcut: ViewModifier {
    @KeptAwake private var awake
    let shortcut: KeyboardShortcut

    func body(content: Content) -> some View { content.keyboardShortcut(awake ? shortcut : nil) }
}

/// The text field being typed in belongs to the view on screen: when another view takes its place the window takes the
/// keyboard back, or typing would go on into a field nobody sees. (The view coming in asks for the keyboard itself,
/// after this.)
@MainActor
enum KeptFocus {
    static func leaveTextField() {
        guard let window = NSApp?.keyWindow, window.firstResponder is NSText else { return }
        window.makeFirstResponder(nil)
    }
}
