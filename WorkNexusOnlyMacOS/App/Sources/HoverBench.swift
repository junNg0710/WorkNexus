import AppKit
import CoreUI
import Foundation

#if DEBUG
/// DEBUG builds only: `WN_DEMO_MOUSE=1` sends mouse moves across the main window 60 times a second (the real pointer does
/// not move), as a hand resting on the mouse makes them, and prints each second the main thread's CPU time - what
/// hovering costs. `WN_DEMO_MOUSE_X=<from>,<to>` (shares of the window's width; the whole of it when not given) keeps the
/// sweep over one part, say the message list. `WN_DEMO_VIEWS=1` also prints, once, how many AppKit views and tracking
/// areas the window holds.
@MainActor
enum MouseSweep {
    private static var timer: Timer?
    private static var step = 0
    private static var sent = 0
    private static var lastCPU: Double = 0
    private static var second = 0

    static func start() {
        let env = ProcessInfo.processInfo.environment
        // `WN_DEMO_FRONT=1`: the app comes to the front first. Tracking areas (hover, the pointer's shape) are only
        // handed moves in the active app, so without it the sweep costs - and measures - nothing.
        if env["WN_DEMO_FRONT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
        }
        let share = (env["WN_DEMO_MOUSE_X"] ?? "").split(separator: ",").compactMap { Double($0) }
        let from = share.count == 2 ? CGFloat(share[0]) : 0, to = share.count == 2 ? CGFloat(share[1]) : 1
        let census = env["WN_DEMO_VIEWS"] == "1", post = env["WN_DEMO_MOUSE_POST"] == "1"
        // `WN_DEMO_HITTEST=1`: no moves are sent; each second what a mouse move starts is called 300 times, along the
        // sweep, and the time one call takes is printed: the window's search for what lies under the point, the hosting
        // view's hover handling, and each other tracking area's own handling (the pointer's shape). Called directly, so it
        // measures the same with the app behind the others, wherever the real pointer is.
        if env["WN_DEMO_HITTEST"] == "1" {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }), let view = w.contentView else { return }
                    second += 1
                    let size = view.bounds.size, edge: CGFloat = 80
                    let left = max(size.width * from, edge), right = min(size.width * to, size.width - edge)
                    let points = (0..<300).map { _ -> NSPoint in
                        step += 1
                        return NSPoint(x: left + CGFloat(step * 7 % Int(max(right - left, 1))), y: edge + CGFloat(step * 3 % Int(max(size.height - edge * 2, 1))))
                    }
                    let events = points.compactMap {
                        NSEvent.mouseEvent(with: .mouseMoved, location: $0, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)
                    }
                    var line = "BENCH hittest \(second):"
                    var began = cpu()
                    for p in points { _ = view.hitTest(p) }
                    line += " hit \(Int((cpu() - began) * 1000 / 300)) us"
                    began = cpu()
                    for e in events { view.mouseMoved(with: e) }
                    line += ", hover \(Int((cpu() - began) * 1000 / 300)) us"
                    for area in view.trackingAreas {
                        guard let owner = area.owner as? NSObject, owner !== view, owner.responds(to: #selector(NSResponder.mouseMoved(with:))) else { continue }
                        began = cpu()
                        for e in events { owner.perform(#selector(NSResponder.mouseMoved(with:)), with: e) }
                        line += ", \(String(describing: type(of: owner)).prefix(24)) \(Int((cpu() - began) * 1000 / 300)) us"
                    }
                    print(line + ", main cpu \(Int(cpu() - lastCPU)) ms")
                    lastCPU = cpu()
                    if census, second == 14 { print("BENCH views: \(ViewCensus.describe(w))") }
                    fflush(stdout)
                }
            }
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }), let view = w.contentView else { return }
                step += 1
                let size = view.bounds.size, edge: CGFloat = 80
                let left = max(size.width * from, edge), right = min(size.width * to, size.width - edge)
                let x = left + CGFloat(step * 7 % Int(max(right - left, 1)))
                let y = edge + CGFloat(step * 3 % Int(max(size.height - edge * 2, 1)))
                if step % 60 == 0 {
                    second += 1
                    let now = cpu()
                    let pace = PointerMovePace.shared
                    print("BENCH hover \(second): main cpu \(Int(now - lastCPU)) ms, \(sent) moves, active \(NSApp.isActive), paced: \(pace.handledAtOnce) at once, \(pace.waited) waited, \(pace.turns) turns")
                    if census, second == 14 { print("BENCH views: \(ViewCensus.describe(w))") }
                    fflush(stdout)
                    lastCPU = now; sent = 0
                }
                guard let e = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: x, y: y), modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: 0, pressure: 0) else { return }
                // Through the app, as a real move is: that is where it is handed to the tracking areas (hover, the
                // pointer's shape). Sent to the window it only reached the first responder, and measured nothing.
                // `WN_DEMO_MOUSE_POST=1`: through the event queue instead, as the system delivers a move.
                if post { NSApp.postEvent(e, atStart: false) } else { NSApp.sendEvent(e) }
                sent += 1
            }
        }
    }

    /// The main thread's CPU time so far, in ms (its own count: `MainCPU` is the switch benches').
    private static func cpu() -> Double {
        var t = timespec(); clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
        return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1_000_000
    }
}

/// How many AppKit views and tracking areas a window holds, and the classes there are most of.
@MainActor
enum ViewCensus {
    static func describe(_ window: NSWindow) -> String {
        guard let root = window.contentView?.superview ?? window.contentView else { return "no views" }
        var views = 0, areas = 0, unseen = 0
        var classes: [String: Int] = [:], areaOwners: [String: Int] = [:]
        var stack: [(NSView, Bool)] = [(root, false)]
        while let (v, hidden) = stack.popLast() {
            let off = hidden || v.isHidden || v.alphaValue == 0 || (v.layer?.opacity ?? 1) == 0
            let name = String(describing: type(of: v))
            views += 1; classes[name, default: 0] += 1
            if off { unseen += 1 }
            if !v.trackingAreas.isEmpty { areas += v.trackingAreas.count; areaOwners[name + (off ? " (unseen)" : ""), default: 0] += v.trackingAreas.count }
            for s in v.subviews { stack.append((s, off)) }
        }
        let top = { (d: [String: Int]) in d.sorted { $0.value > $1.value }.prefix(14).map { "\($0.key) \($0.value)" }.joined(separator: ", ") }
        return "\(views) views (\(unseen) unseen), \(areas) tracking areas | classes: \(top(classes)) | areas: \(top(areaOwners))"
    }
}
#endif
