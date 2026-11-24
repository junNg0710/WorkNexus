import SwiftUI

private struct SectionActiveKey: EnvironmentKey { static let defaultValue = true }
public extension EnvironmentValues {
    /// False while a view is kept mounted behind the one on screen (`KeptAlive`): it should not register shortcuts,
    /// grab focus or start work that is only for a visible section.
    var sectionIsActive: Bool {
        get { self[SectionActiveKey.self] }
        set { self[SectionActiveKey.self] = newValue }
    }
}

/// Which kept view is on screen, and which one just left it and has not been put to sleep yet. A class so the body can
/// note the view on screen without a state change loop (it is only read by the same body that wrote it).
@MainActor
public final class KeepAliveWake {
    public private(set) var shown: String?
    public private(set) var leaving: String?

    public init() {}

    /// Notes which view is on screen now. The one it replaces stays awake until `settle()`.
    public func show(_ key: String?) {
        guard key != shown else { return }
        leaving = shown
        shown = key
    }

    public func settle() { leaving = nil }

    /// Whether a view runs (enabled, animating, counted as the active section): the one on screen and the one leaving.
    public func isAwake(_ key: String) -> Bool { key == shown || key == leaving }
}

/// Views kept mounted one over the other with only `shown` on screen: the shell's places, the chats last opened. Each
/// view of `content` is marked with `keptAlive(_:active:awake:front:)`.
///
/// A view that leaves the screen is hidden at once and put to sleep a frame later: disabling it, pausing its animations
/// and telling it it is not the active section each walk its whole tree, and doing that for the view leaving in the same
/// frame that wakes the one coming in made that frame twice as heavy.
public struct KeptAlive<Content: View>: View {
    private let shown: String?
    private let content: (KeepAliveWake) -> Content
    @State private var wake = KeepAliveWake()
    /// Counts the views put to sleep: changing it draws the stack again once `wake.settle()` has run.
    @State private var settled = 0

    /// `content` is given what tells whether the view with a key is awake (`KeepAliveWake.isAwake`).
    public init(shown: String?, @ViewBuilder content: @escaping (KeepAliveWake) -> Content) {
        self.shown = shown
        self.content = content
    }

    public var body: some View {
        wake.show(shown)
        _ = settled
        let wake = wake
        return KeepAliveLayout { content(wake) }
            .task(id: shown) {
                await NextDisplayFrame.wait()
                guard !Task.isCancelled, wake.leaving != nil else { return }
                wake.settle()
                settled += 1
            }
    }
}

public extension View {
    /// One view of a `KeptAlive` stack: off screen it is invisible and takes no clicks at once (`active`), and stops
    /// running — disabled, so no shortcuts or focus, its animations paused, not the active section — once it is not
    /// `awake`. `front` puts it over the others.
    func keptAlive(_ key: String, active: Bool, awake: Bool, front: Bool) -> some View {
        environment(\.sectionIsActive, awake)
            .environment(\.animationsRun, awake)
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .disabled(!awake)
            .accessibilityHidden(!awake)
            .zIndex(front ? 1 : 0)
            .keepAlivePlace(key, active: active)
    }
}
