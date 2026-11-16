import AppKit
import SwiftUI
import XCTest

/// Probe: which drag modifier evaluates its closure only when a drag starts (so it can mark the dragged card)?
/// `.draggable(_:preview:)` evaluates its preview eagerly (12 times for 3 cards when rendered); `.onDrag`'s data
/// closure must not run until a drag begins.
@MainActor
final class DragPreviewProbeTests: XCTestCase {
    final class Counter { var n = 0 }

    private func host<V: View>(_ view: V) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: view.frame(width: 200, height: 200))
        host.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        return host
    }

    func testOnDragDoesNotEvaluateItsDataClosureWhileRendering() {
        let c = Counter()
        let view = VStack {
            ForEach(0..<3) { i in
                Text("card \(i)").onDrag({ c.n += 1; return NSItemProvider(object: "id\(i)" as NSString) }, preview: { Text("preview") })
            }
        }
        _ = host(view)
        XCTAssertEqual(c.n, 0, "the data closure is the drag-start hook")
    }
}
