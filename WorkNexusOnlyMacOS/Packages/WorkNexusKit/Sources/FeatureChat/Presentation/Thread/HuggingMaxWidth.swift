import SwiftUI

/// Sizes its one child to what it needs, up to `maxWidth`. (`.frame(maxWidth:)` is not that: given more room than the cap
/// it takes the cap even for a short child, so a short bubble got a 745 pt wide cell and the hover buttons beside it sat
/// far from the bubble itself.) A child that fills what it is offered - a quote, a link card - still gets `maxWidth`.
struct HuggingMaxWidth: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(proposal.width ?? maxWidth, maxWidth)
        return child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

extension View {
    /// At most `width` wide, and no wider than its content needs (see `HuggingMaxWidth`).
    func hugging(maxWidth width: CGFloat) -> some View { HuggingMaxWidth(maxWidth: width) { self } }
}
