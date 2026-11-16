/// Ported from: lib/features/chat/presentation/widgets/chat_avatar_crop_view.dart + chat_avatar_crop_mask.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// The whole picture, fitted in `maxSize`, under a square frame: drag the frame to move it, a corner to resize it. The round
/// mask shows what the avatar keeps; `onChange` reports that square in the picture's own pixels.
struct ChatAvatarCropView: View {
    @Environment(\.appTheme) private var theme
    let image: NSImage
    let imageSize: CGSize
    let maxSize: CGSize
    let onChange: (ChatAvatarCrop) -> Void
    @State private var geometry: AvatarCropGeometry?
    @State private var lastDrag: CGSize = .zero
    @State private var resize: AvatarCropGeometry.Resize?

    private var grip: CGFloat { theme.sizes.control32 }

    var body: some View {
        let g = geometry ?? AvatarCropGeometry(imageSize: imageSize, maxSize: maxSize, grip: grip)
        // Everything is laid out `margin` in, so the grips stay hittable.
        let margin = grip / 2
        let frame = g.frame.offsetBy(dx: margin, dy: margin)
        ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable().frame(width: g.shown.width, height: g.shown.height).offset(x: margin, y: margin)
            Canvas { ctx, _ in
                var dim = Path(CGRect(x: margin, y: margin, width: g.shown.width, height: g.shown.height))
                dim.addEllipse(in: frame)
                ctx.fill(dim, with: .color(theme.colors.scrim.opacity(0.55)), style: FillStyle(eoFill: true))
                ctx.stroke(Path(frame), with: .color(theme.colors.onScrim.opacity(0.6)), lineWidth: theme.borders.hairline)
                ctx.stroke(Path(ellipseIn: frame.insetBy(dx: theme.borders.thick / 2, dy: theme.borders.thick / 2)),
                           with: .color(theme.colors.onScrim), lineWidth: theme.borders.thick)
                for c in AvatarCropGeometry.corners {
                    let p = g.point(c, in: frame), r = theme.spacing.s6
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(theme.colors.onScrim))
                }
            }
            .allowsHitTesting(false)
            Color.clear.contentShape(Rectangle()).frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                .onHover { $0 ? NSCursor.openHand.push() : NSCursor.pop() }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        var next = g
                        next.move(by: CGSize(width: v.translation.width - lastDrag.width, height: v.translation.height - lastDrag.height))
                        lastDrag = v.translation; geometry = next; onChange(next.crop)
                    }
                    .onEnded { _ in lastDrag = .zero })
            ForEach(AvatarCropGeometry.corners, id: \.self) { corner in
                let p = g.point(corner, in: frame)
                Color.clear.contentShape(Rectangle()).frame(width: grip, height: grip).position(x: p.x, y: p.y)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            var next = g
                            var r = resize ?? g.beginResize(corner)
                            next.resize(corner, by: CGSize(width: v.translation.width - lastDrag.width, height: v.translation.height - lastDrag.height), &r)
                            resize = r; lastDrag = v.translation; geometry = next; onChange(next.crop)
                        }
                        .onEnded { _ in resize = nil; lastDrag = .zero })
            }
        }
        .frame(width: g.shown.width + grip, height: g.shown.height + grip, alignment: .topLeading)
        .onAppear { geometry = g; onChange(g.crop) }
    }
}
