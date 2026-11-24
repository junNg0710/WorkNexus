import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_apps_host.dart
/// Holds the mini apps used most recently, showing only the current one. The others stay mounted (hidden) so switching on
/// the rail does not reload a page or sign the user out. Each one is a whole web process, so only
/// `MiniAppsSettings.liveLimit` are kept (`MiniAppsModel` decides which). Put it once in the shell's content area. `bars` is
/// the fold of the bars over the pages, which the app keeps.
public struct MiniAppsHostStack: View {
    @Environment(\.miniApps) private var feature
    private let bars: MiniAppBars
    public init(bars: MiniAppBars = MiniAppBars()) { self.bars = bars }

    public var body: some View {
        if let model = feature?.model {
            ZStack {
                ForEach(model.apps.filter { model.liveIds.contains($0.id) }) { app in
                    let current = app.id == model.currentId
                    MiniAppHostView(miniApp: app, active: model.onScreen && current)
                        .opacity(current ? 1 : 0).allowsHitTesting(current).accessibilityHidden(!current)
                }
            }
            .opacity(model.onScreen ? 1 : 0).allowsHitTesting(model.onScreen)
            .environment(\.miniAppBars, bars)
        }
    }
}
