import AppKit
import SwiftUI

/// Ported from: lib/core/widgets/image_viewer_dialog.dart (the `InteractiveViewer` part) and the attachment viewer's
/// `InteractiveViewer(maxScale: 5)`.
/// An image that fits its space and can be zoomed (mouse wheel, ctrl/cmd + scroll, pinch), panned (drag, two-finger
/// scroll) and double-clicked to zoom in about the pointer or back to fit. `onBackgroundTap` fires for a click beside
/// the picture (the viewer closes on it); a click on the picture does nothing.
public struct ZoomableImage: View {
    @State private var zoom = ImageZoom()
    @State private var dragStart: CGSize?
    @State private var pinchStart: ImageZoom?
    let image: NSImage
    let minScale: CGFloat
    let maxScale: CGFloat
    let inset: CGFloat
    let onBackgroundTap: (() -> Void)?

    public init(image: NSImage, minScale: CGFloat = 0.5, maxScale: CGFloat = 8, inset: CGFloat = 0, onBackgroundTap: (() -> Void)? = nil) {
        self.image = image; self.minScale = minScale; self.maxScale = maxScale; self.inset = inset; self.onBackgroundTap = onBackgroundTap
    }

    private func clamped(_ z: ImageZoom, _ size: CGSize) -> ImageZoom {
        var z = z
        z.scale = min(max(z.scale, minScale), maxScale)
        let limit = CGSize(width: size.width * z.scale / 2, height: size.height * z.scale / 2)
        z.offset.width = min(max(z.offset.width, -limit.width), limit.width)
        z.offset.height = min(max(z.offset.height, -limit.height), limit.height)
        return z
    }

    private func center(_ p: CGPoint, _ size: CGSize) -> CGPoint { CGPoint(x: p.x - size.width / 2, y: p.y - size.height / 2) }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZoomablePicture(image: image).padding(inset)
                .frame(width: size.width, height: size.height)
                .scaleEffect(zoom.scale).offset(zoom.offset)
                .frame(width: size.width, height: size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(DragGesture()
                    .onChanged { g in
                        let start = dragStart ?? zoom.offset
                        dragStart = start
                        zoom = clamped(ImageZoom(scale: zoom.scale, offset: CGSize(width: start.width + g.translation.width, height: start.height + g.translation.height)), size)
                    }
                    .onEnded { _ in dragStart = nil })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { g in
                        let start = pinchStart ?? zoom
                        pinchStart = start
                        zoom = clamped(start.zoomed(to: start.scale * g.magnification, about: center(g.startLocation, size)), size)
                    }
                    .onEnded { _ in pinchStart = nil })
                .onTapGesture(count: 2, coordinateSpace: .local) { at in
                    withAnimation(.easeOut(duration: 0.18)) {
                        zoom = clamped(zoom.toggled(about: center(at, size), zoomedScale: 2.5), size)
                    }
                }
                .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                    guard let onBackgroundTap else { return }
                    if !pictureRect(in: size).contains(tap.location) { onBackgroundTap() }
                })
                .background(ScrollZoomCatcher { delta, precise, flags, location in
                    var next = zoom
                    if precise && flags.isDisjoint(with: [.command, .control]) {
                        next.offset.width += delta.width; next.offset.height += delta.height
                    } else {
                        let factor = pow(1.1, delta.height * (precise ? 0.2 : 1))
                        next = zoom.zoomed(to: zoom.scale * factor, about: center(location, size), minScale: minScale, maxScale: maxScale)
                    }
                    zoom = clamped(next, size)
                })
        }
    }

    /// Where the picture is on screen (fit into the space, then zoomed and panned).
    private func pictureRect(in size: CGSize) -> CGRect {
        let avail = CGSize(width: max(size.width - inset * 2, 1), height: max(size.height - inset * 2, 1))
        let natural = image.size.width > 0 && image.size.height > 0 ? image.size : CGSize(width: 1, height: 1)
        let fit = min(avail.width / natural.width, avail.height / natural.height)
        let w = natural.width * fit * zoom.scale, h = natural.height * fit * zoom.scale
        return CGRect(x: size.width / 2 + zoom.offset.width - w / 2, y: size.height / 2 + zoom.offset.height - h / 2, width: w, height: h)
    }
}

/// A zoom level and pan, with the maths of zooming about a point (`q` is the point relative to the view's centre).
struct ImageZoom: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    func zoomed(to newScale: CGFloat, about q: CGPoint, minScale: CGFloat = 0.01, maxScale: CGFloat = 1000) -> ImageZoom {
        let target = min(max(newScale, minScale), maxScale)
        let ratio = target / scale
        return ImageZoom(scale: target, offset: CGSize(width: q.x - ratio * (q.x - offset.width), height: q.y - ratio * (q.y - offset.height)))
    }

    /// Back to fit when zoomed in, else in to `zoomedScale` about `q` (what was clicked stays under the pointer).
    func toggled(about q: CGPoint, zoomedScale: CGFloat) -> ImageZoom {
        scale > 1.01 ? ImageZoom() : ImageZoom().zoomed(to: zoomedScale, about: q)
    }
}

/// Hears the wheel over its area (a local monitor, so it takes no clicks): hands the delta, whether it is a precise
/// (trackpad) delta, the modifiers and the pointer in the area's own top-left coordinates.
private struct ScrollZoomCatcher: NSViewRepresentable {
    let onScroll: (CGSize, Bool, NSEvent.ModifierFlags, CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) { v.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: ((CGSize, Bool, NSEvent.ModifierFlags, CGPoint) -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(p) else { return event }
                self.onScroll?(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY), event.hasPreciseScrollingDeltas, event.modifierFlags, p)
                return nil
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// The picture itself: a GIF with frames plays (`NSImageView` animates them); a still picture is a plain image.
private struct ZoomablePicture: View {
    let image: NSImage
    var body: some View {
        if image.isAnimatedGIF { AnimatedImageView(image: image) } else { Image(nsImage: image).resizable().scaledToFit() }
    }
}

private struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage
    func makeNSView(context: Context) -> NSImageView {
        let v = NoDropImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.animates = true
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }
    func updateNSView(_ v: NSImageView, context: Context) { if v.image !== image { v.image = image } }
}

extension NSImage {
    /// A GIF with more than one frame.
    var isAnimatedGIF: Bool {
        representations.contains { (($0 as? NSBitmapImageRep)?.value(forProperty: .frameCount) as? Int ?? 0) > 1 }
    }
}
