import AppKit

/// DEBUG only: `WN_DEMO_DRAGVIEWS=<seconds>` writes every view that takes drags (what AppKit can route a dragged file to)
/// with its frame in its window, after that many seconds and again every few seconds, to trace a drop that never lands.
enum DragViewsProbe {
    @MainActor
    static func start() {
        #if DEBUG
        guard let delay = ProcessInfo.processInfo.environment["WN_DEMO_DRAGVIEWS"].flatMap(Double.init) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            for round in 0..<3 {
                for window in NSApp.windows where window.isVisible {
                    guard let root = window.contentView else { continue }
                    var lines: [String] = []
                    func walk(_ v: NSView, _ path: [String]) {
                        let name = String(describing: type(of: v))
                        let short = String(name.prefix(70))
                        if !v.registeredDraggedTypes.isEmpty {
                            let f = v.convert(v.bounds, to: nil)
                            lines.append("  \(short) frame=(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))) hidden=\(v.isHiddenOrHasHiddenAncestor) "
                                         + "types=\(v.registeredDraggedTypes.map(\.rawValue).prefix(4)) under=\(path.suffix(2).joined(separator: " > "))")
                        }
                        v.subviews.forEach { walk($0, path + [short]) }
                    }
                    walk(root, [])
                    FileHandle.standardError.write(Data("DRAGVIEWS round \(round) window '\(window.title)' \(Int(window.frame.width))x\(Int(window.frame.height)):\n\(lines.joined(separator: "\n"))\n".utf8))
                }
                try? await Task.sleep(for: .seconds(4))
            }
            // `WN_DEMO_DROP=<x>,<y>;<x>,<y>` (window points from the top-left) and `WN_DEMO_DROP_FILE=<path>`: drops that file
            // at each point on the view AppKit would hand the drag to there, and says which view took it and how.
            guard let spec = ProcessInfo.processInfo.environment["WN_DEMO_DROP"],
                  let path = ProcessInfo.processInfo.environment["WN_DEMO_DROP_FILE"],
                  let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }), let root = window.contentView else { return }
            for pair in spec.split(separator: ";") {
                let v = pair.split(separator: ",").compactMap { Double($0) }
                guard v.count == 2 else { continue }
                let point = NSPoint(x: v[0], y: root.bounds.height - v[1])
                // AppKit hands a drag to the frontmost view under the pointer that registered for drags.
                var target: NSView?
                func walk(_ view: NSView) {
                    if !view.registeredDraggedTypes.isEmpty, !view.isHiddenOrHasHiddenAncestor, view.convert(view.bounds, to: nil).contains(point) { target = view }
                    view.subviews.forEach(walk)
                }
                walk(root)
                let drag = ProbeDrag(url: URL(fileURLWithPath: path), at: point, in: window)
                let dest = target as NSDraggingDestination?
                let op = dest?.draggingEntered?(drag) ?? []
                let done = op != [] && (dest?.prepareForDragOperation?(drag) ?? true) && (dest?.performDragOperation?(drag) ?? false)
                FileHandle.standardError.write(Data("DROP at \(Int(v[0])),\(Int(v[1])): \(target.map { String(describing: type(of: $0)).prefix(60) } ?? "nothing") op=\(op.rawValue) done=\(done)\n".utf8))
                try? await Task.sleep(for: .seconds(2))
            }
        }
        #endif
    }
}

#if DEBUG
/// A file dragged over a window, as AppKit describes it to the view under the pointer.
@MainActor
private final class ProbeDrag: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingLocation: NSPoint
    weak var window: NSWindow?
    init(url: URL, at point: NSPoint, in window: NSWindow) {
        draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("wn-probe-\(UUID().uuidString)"))
        draggingPasteboard.clearContents()
        draggingPasteboard.writeObjects([url as NSURL])
        draggingLocation = point; self.window = window
    }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .generic, .link] }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 7 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}
#endif
