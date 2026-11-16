import SwiftUI

/// The icons of the buttons that fold a side panel away and bring it back, so each says what a click does: folding a
/// panel on the `leading` side points at that edge (``«``), unfolding it points away from it (``»``); the trailing side
/// is the mirror. (A single "sidebar" glyph for both told nothing about the state.)
public enum AppPanelIcon {
    public static func collapse(_ side: HorizontalEdge) -> String { side == .leading ? "chevron.left.2" : "chevron.right.2" }
    public static func expand(_ side: HorizontalEdge) -> String { side == .leading ? "chevron.right.2" : "chevron.left.2" }
}
