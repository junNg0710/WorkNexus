import SwiftUI

/// The icon of a button that folds a side panel away or brings it back: a window with the panel as a strip on one side and a
/// chevron in the rest of it. Folding shows the outlined window with the chevron pointing at the panel's edge (the panel
/// goes that way); unfolding shows the window filled, the chevron pointing away from it (the panel comes back). So the
/// icon says what a click does, and in which state the panel is. Not in the Flutter app.
public struct PanelToggleGlyph: View {
    public enum Action: Sendable { case collapse, expand }

    @Environment(\.appTheme) private var theme
    let action: Action
    /// The side the panel is on.
    let side: HorizontalEdge
    let size: CGFloat

    public init(_ action: Action, side: HorizontalEdge = .leading, size: CGFloat = 16) {
        self.action = action; self.side = side; self.size = size
    }

    public var body: some View {
        Canvas { context, canvas in
            let w = canvas.width, h = canvas.height
            let line = max(w * 0.1, 1.3)
            let frame = CGRect(x: line / 2, y: h * 0.1 + line / 2, width: w - line, height: h * 0.8 - line)
            let radius = frame.height * 0.28
            let panelEdge = frame.minX + frame.width * 0.34
            let midY = frame.midY
            // The chevron sits in the part of the window that is not the panel.
            let cx = (panelEdge + frame.maxX) / 2, reach = frame.height * 0.22
            let pointsAtPanel = action == .collapse
            var chevron = Path()
            let tipX = cx + (pointsAtPanel ? -reach : reach) * 0.55, backX = cx + (pointsAtPanel ? reach : -reach) * 0.55
            chevron.move(to: CGPoint(x: backX, y: midY - reach))
            chevron.addLine(to: CGPoint(x: tipX, y: midY))
            chevron.addLine(to: CGPoint(x: backX, y: midY + reach))
            var divider = Path()
            divider.move(to: CGPoint(x: panelEdge, y: frame.minY)); divider.addLine(to: CGPoint(x: panelEdge, y: frame.maxY))
            let ink = GraphicsContext.Shading.foreground
            let stroke = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            let body = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: frame)

            if action == .collapse {
                context.stroke(body, with: ink, style: stroke)
                context.stroke(divider, with: ink, style: stroke)
                context.stroke(chevron, with: ink, style: stroke)
            } else {
                context.drawLayer { layer in
                    layer.fill(body, with: ink)
                    // The divider and the chevron are cut out of the filled window.
                    layer.blendMode = .destinationOut
                    layer.stroke(divider, with: .color(.black), style: StrokeStyle(lineWidth: line * 0.9, lineCap: .butt))
                    layer.stroke(chevron, with: .color(.black), style: stroke)
                }
            }
        }
        .frame(width: size * 1.4, height: size * 1.4)
        // The panel strip is on the right for a panel on the trailing side: the same icon, mirrored.
        .scaleEffect(x: side == .leading ? 1 : -1, y: 1)
        .accessibilityHidden(true)
    }
}
