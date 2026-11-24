import CoreUI
import SwiftUI

/// The fold of the bars over a mini app's page: collapsed, the window's title bar and the browser bar give their room to
/// the page and only the tab strip stays, with the button that brings them back. The app keeps the choice (in its
/// settings) and folds its title bar along; `setCollapsed` is called inside an animation, so both move together.
public struct MiniAppBars {
    public var collapsed: Bool
    public var setCollapsed: (Bool) -> Void

    public init(collapsed: Bool = false, setCollapsed: @escaping (Bool) -> Void = { _ in }) {
        self.collapsed = collapsed; self.setCollapsed = setCollapsed
    }

    /// Folds the bars or brings them back, sliding.
    @MainActor func set(_ collapsed: Bool) {
        guard collapsed != self.collapsed else { return }
        withAnimation(.easeInOut(duration: AppMotion().slow)) { setCollapsed(collapsed) }
    }

    /// The button is one arrow that turns over (up: fold away, down: bring back). Two symbols would be swapped where the
    /// button stood, while the strip under it slides off.
    static let symbol = "chevron.up"
    var turn: Angle { .degrees(collapsed ? 180 : 0) }
    var help: String {
        collapsed ? appString("miniAppExpandBars", "Show the top bars") : appString("miniAppCollapseBars", "Hide the top bars")
    }
}

private struct MiniAppBarsKey: EnvironmentKey {
    static var defaultValue: MiniAppBars { MiniAppBars() }
}

extension EnvironmentValues {
    /// The fold of the bars over the mini apps' pages; set by `MiniAppsHostStack`.
    var miniAppBars: MiniAppBars {
        get { self[MiniAppBarsKey.self] }
        set { self[MiniAppBarsKey.self] = newValue }
    }
}
