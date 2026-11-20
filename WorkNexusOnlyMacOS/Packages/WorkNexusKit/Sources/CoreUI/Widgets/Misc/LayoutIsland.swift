/// Not in the Flutter app.
import SwiftUI

/// Lays `content` out in the room it is given, and keeps what changes inside it from re-measuring what is around it.
///
/// A scrolling lazy list changes its content size all the time (rows are measured as they come in), and SwiftUI then
/// re-measures the list's ancestors and their other children: the header, the composer, the pane beside it, up through
/// the window. With a chat scrolling that was most of every frame's work — twice the list's own — and what a slower Mac
/// could not keep up with. An overlay's size never reaches the view it lies on, so the list's changes stop here.
/// For content that fills its room (a `ScrollView`); content with a size of its own would be centred in it.
public struct LayoutIsland<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        Color.clear.overlay { content }
    }
}
