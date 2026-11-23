/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SwiftUI

/// The keys held down that the rail answers by showing, on each place, what opens it with them: hold ⌘ and the first ten
/// places show 1 … 0, the next ten ⌥1 … ⌥0. It waits a moment first, so a quick ⌘C or ⌘V shows nothing.
@MainActor @Observable
public final class RailKeyHints {
    /// The modifiers the hints are shown for; nil: no hints.
    public private(set) var held: KeyShortcut.Modifiers?
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// How long ⌘ (or ⌃) is held before the hints come up.
    public static let delay: Duration = .milliseconds(300)

    public init() {}

    /// The modifiers held changed (none: released, or the window is no longer the one typed into).
    public func modifiersChanged(_ modifiers: KeyShortcut.Modifiers, after delay: Duration = RailKeyHints.delay) {
        pending?.cancel(); pending = nil
        // ⇧ and ⌥ alone are typing, not the start of a shortcut.
        guard !modifiers.isDisjoint(with: [.command, .control]) else {
            if held != nil { held = nil }
            return
        }
        // Already up: another modifier added or let go shows its own keys at once.
        if held != nil { held = modifiers; return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.held = modifiers
        }
    }
}

public extension ShellModel {
    /// What a place of the rail shows while modifiers of its shortcut are held: what is left to press with them (`1`
    /// under ⌘ for ⌘1, `⌥1` for ⌥⌘1); nil otherwise. `keys` are the rail's shortcuts when the caller already has them.
    func railKeyHint(_ place: String, keys: [String: KeyShortcut]? = nil) -> String? {
        guard let held = railHints.held else { return nil }
        return (keys ?? railShortcuts)[place]?.hint(whileHolding: held)
    }
}

public extension View {
    /// Shows `key` on the corner of a rail button (the key that opens its place with the modifiers held); nil: nothing.
    func railKeyHint(_ key: String?) -> some View { modifier(RailKeyHintBadge(key: key)) }
}

private struct RailKeyHintBadge: ViewModifier {
    @Environment(\.appTheme) private var theme
    let key: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            if let key {
                Text(key).font(theme.typography.badge).foregroundStyle(theme.colors.accentTx)
                    .padding(.horizontal, theme.spacing.s4).frame(minWidth: theme.sizes.icon16, minHeight: theme.sizes.icon16)
                    .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: theme.radii.sm))
                    .padding(theme.spacing.s2)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: theme.motion.fast), value: key)
    }
}
