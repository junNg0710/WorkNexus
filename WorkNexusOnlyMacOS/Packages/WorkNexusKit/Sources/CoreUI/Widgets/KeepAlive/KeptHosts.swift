import AppKit
import SwiftUI

/// Views kept alive each in a hosting view of its own, only `shown` on screen. An experiment (off unless
/// `KeptHosts.isOn`): the chats last opened.
///
/// `KeptAlive` keeps its views in the window's one view tree, where a hidden view is still there for everything that
/// walks the tree: every hit test of a pointer move goes through it (measured: each kept view adds to every hit test,
/// whatever hides it), a change of focus visits it when an app reads the window through accessibility, and showing
/// another view costs more the more are kept. Here each kept view is a tree of its own under an AppKit view that is
/// simply hidden: nothing of the window's tree reaches into it, and AppKit leaves a hidden view out of hit tests, the
/// key-view loop and accessibility by itself.
///
/// What a kept view reads from around it is the environment, handed over when it is shown and while it is shown; a
/// hidden one goes on with the environment it had. `@KeptAwake` works inside as in `KeptAlive`.
public struct KeptHosts<Content: View>: View {
    private let shown: String?
    private let keys: [String]
    private let content: (String) -> Content
    @Environment(KeepAlivePresence.self) private var around: KeepAlivePresence?
    @State private var wake = KeepAliveWake()

    /// `keys`: the views kept now; `content` builds the view of a key (asked when it is first kept and when shown).
    public init(shown: String?, keys: [String], @ViewBuilder content: @escaping (String) -> Content) {
        self.shown = shown
        self.keys = keys
        self.content = content
    }

    public var body: some View {
        wake.prepare(shown: shown, keys: keys, around: around)
        return KeptHostsRepresentable(shown: shown, keys: keys, wake: wake, content: content)
            .onChange(of: shown) { _, key in wake.show(key) }
    }
}

public enum KeptHostsExperiment {
    /// Whether kept chats get a tree of their own: `defaults write com.worknexus.macos experiments.keptHosts -bool YES`
    /// (or `WN_KEPT_HOSTS=1` for one run). Read once: it does not change under a window that is open.
    public static let isOn: Bool = ProcessInfo.processInfo.environment["WN_KEPT_HOSTS"] == "1"
        || UserDefaults.standard.bool(forKey: "experiments.keptHosts")
}

private struct KeptHostsRepresentable<Content: View>: NSViewRepresentable {
    let shown: String?
    let keys: [String]
    let wake: KeepAliveWake
    let content: (String) -> Content

    func makeNSView(context: Context) -> KeptHostsView { KeptHostsView() }

    func updateNSView(_ view: KeptHostsView, context: Context) {
        let environment = context.environment, wake = wake, content = content
        view.update(keys: keys, shown: shown) { key in
            AnyView(content(key).environment(\.self, environment).environment(wake.presence(key)))
        }
    }
}

/// The hosting views of `KeptHosts`, one per key, all the size of this view; only the shown one is not hidden.
final class KeptHostsView: NSView {
    private var hosts: [String: NSHostingView<AnyView>] = [:]
    private var shown: String?

    override var isFlipped: Bool { true }

    func update(keys: [String], shown: String?, root: (String) -> AnyView) {
        for (key, host) in hosts where !keys.contains(key) {
            host.removeFromSuperview()
            hosts[key] = nil
        }
        for key in keys {
            if let host = hosts[key] {
                // Only the view on screen follows what is around it; a hidden one is left alone until it is shown.
                if key == shown { host.rootView = root(key) }
            } else {
                let host = NSHostingView(rootView: root(key))
                host.sizingOptions = []
                host.safeAreaRegions = []
                host.frame = bounds
                host.isHidden = key != shown
                addSubview(host)
                hosts[key] = host
                // Built now, also behind the view on screen: a view kept ahead of its first visit is ready for it.
                host.layoutSubtreeIfNeeded()
            }
        }
        for (key, host) in hosts {
            let hide = key != shown
            if !hide, host.frame != bounds { host.frame = bounds }
            if host.isHidden != hide { host.isHidden = hide }
        }
        self.shown = shown
    }

    override func layout() {
        super.layout()
        // A hidden view keeps the size it last had on screen and takes the new one when it is shown.
        if let shown, let host = hosts[shown], host.frame != bounds { host.frame = bounds }
    }

    /// A shortcut is the shown view's only.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let shown, let host = hosts[shown] else { return false }
        return host.performKeyEquivalent(with: event)
    }
}
