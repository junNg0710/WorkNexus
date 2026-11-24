import CoreUI
import SwiftUI

/// Which views `KeepAliveStack` has mounted and what each last showed. A class so the body can refresh it without a state
/// change loop (it is only read by the same body that wrote it).
@MainActor
final class KeepAliveStore {
    var lru: KeepAliveLRU
    var views: [String: AnyView] = [:]
    init(limit: Int) { lru = KeepAliveLRU(limit: limit) }

    func remember(_ key: String?, _ view: AnyView) {
        guard let key else { return }
        views[key] = view
        if let evicted = lru.touch(key) { views[evicted] = nil }
    }
    func removeAll() { lru.removeAll(); views = [:] }
}

/// Ported from: lib/app/shell/viewport.dart (`_updateCache` + the `IndexedStack`) and tool_pane_host.dart: the last `limit`
/// places stay mounted — hidden ones keep their filters, search text, scroll position and open branches — and the least
/// recently used one is dropped to make room. `visible: false` hides all of them (an editor or a mini app covers the area).
/// A hidden view keeps the size it last had on screen (`KeepAliveLayout`) but is invisible, ignores clicks, and reads
/// `@KeptAwake` as false (`KeptAlive`).
struct KeepAliveStack: View {
    let activeKey: String?
    var visible = true
    var limit = 5
    /// Changing this empties the cache (a workspace switch: the old workspace's views would only hold memory).
    var generation = 0
    let content: AnyView?
    @State private var store: KeepAliveStore
    @State private var seenGeneration = 0

    init(activeKey: String?, visible: Bool = true, limit: Int = 5, generation: Int = 0, content: AnyView?) {
        self.activeKey = activeKey; self.visible = visible; self.limit = limit; self.generation = generation; self.content = content
        _store = State(initialValue: KeepAliveStore(limit: limit))
    }

    var body: some View {
        if seenGeneration != generation { store.removeAll() }
        if let content { store.remember(activeKey, content) }
        return KeptAlive(shown: visible ? activeKey : nil, keys: store.lru.keys) { wake in
            ForEach(store.lru.keys, id: \.self) { key in
                let active = key == activeKey && visible
                if let view = store.views[key] {
                    view
                        // Anchored to the top and as large as the viewport: a section whose content is still small (a
                        // loading skeleton) was centred in the window, leaving an empty band above its header.
                        // minWidth/minHeight 0: never larger than the viewport, however wide its content wants to be.
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                        .keptAlive(key, active: active, presence: wake.presence(key), front: key == activeKey)
                }
            }
        }
        .onChange(of: generation, initial: true) { _, g in seenGeneration = g }
    }
}
