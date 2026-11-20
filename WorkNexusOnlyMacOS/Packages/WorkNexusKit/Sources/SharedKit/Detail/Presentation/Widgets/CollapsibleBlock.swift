import CoreUI
import SwiftUI

/// Not in the Flutter app.
/// A block (a comment, an activity's note) shown up to `collapsedHeight` tall, then "Show more" to read it all and "Show
/// less" to fold it back. A block that fits shows whole with no button. Its own height is measured as laid out, so it
/// holds for plain text and rich HTML alike.
struct CollapsibleBlock<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let collapsedHeight: CGFloat
    let content: Content
    @State private var height: CGFloat = 0
    @State private var expanded = false

    init(collapsedHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.collapsedHeight = collapsedHeight; self.content = content()
    }

    /// A little over the cap still shows whole: folding away one line would only add a button.
    private var overflows: Bool { height > collapsedHeight * 1.25 }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .frame(maxHeight: overflows && !expanded ? collapsedHeight : nil, alignment: .top)
                .clipped()
                .mask {
                    // The folded text fades out at the cut instead of stopping mid-line.
                    if overflows && !expanded {
                        LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .black.opacity(0.15), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        Rectangle()
                    }
                }
            if overflows {
                Button { withAnimation(.easeOut(duration: theme.motion.base)) { expanded.toggle() } } label: {
                    HStack(spacing: theme.spacing.s4) {
                        Text(expanded ? appString("detailShowLess", "Show less") : appString("detailShowMore", "Show more"))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: theme.sizes.icon12))
                    }
                    .font(theme.typography.metaStrong).foregroundStyle(theme.colors.accent)
                }
                .buttonStyle(.plain).pointerStyle(.link)
            }
        }
    }
}
