import AppKit
import Foundation
import CoreDomain
import CoreTools
import SharedKit

/// DEBUG builds only: `WN_DEMO_PLACE_CYCLE=chat,account:<id>:<section>,…` walks the rail through those places in turn, one
/// every `WN_DEMO_PLACE_CYCLE_SECONDS` (default 3), and prints the longest gap between screen frames in the second after
/// each switch — the cost of going from one section to another, measured on a copied database without anyone clicking.
enum PlaceSwitchBench {
    @MainActor
    static func start(shell: ShellModel, services: AppServices) {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        ChatScrollBench.start()
        MenuLog.start(); MenuLog.clicks()
        DemoKeys.start(shell: shell)
        DemoType.start()
        SpamClickBench.start()
        guard let spec = env["WN_DEMO_PLACE_CYCLE"] else { return }
        let places = spec.split(separator: ",").map { $0.split(separator: ":").map(String.init) }
        let pause = env["WN_DEMO_PLACE_CYCLE_SECONDS"].flatMap(Double.init) ?? 3
        guard !places.isEmpty else { return }
        let frames = FrameGaps()
        // `WN_DEMO_MOUSE=1`: mouse moves sweep across the window 60 times a second, sent to the window itself (the real
        // pointer does not move), as a hand resting on the mouse makes them.
        if env["WN_DEMO_MOUSE"] == "1" { MouseSweep.start() }
        // `WN_DEMO_TICKET_CHURN=<n>`: rewrites n tickets every half second, as a sync does, so the switches are measured
        // while the ticket list keeps changing.
        if let churn = env["WN_DEMO_TICKET_CHURN"].flatMap(Int.init), churn > 0 {
            Task.detached {
                var all: [Ticket] = []
                for await v in services.tickets.watchTickets() { all = v; break }
                guard !all.isEmpty else { return }
                var round = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    round += 1
                    let batch = (0..<churn).map { i -> Ticket in
                        var t = all[(round * churn + i) % all.count]; t.updatedAt = Date(); return t
                    }
                    _ = await services.tickets.upsertTickets(batch)
                }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            var i = 0
            while !Task.isCancelled {
                let p = places[i % places.count]
                // Kept on top (without taking the keyboard): a covered window draws nothing and would measure nothing.
                NSApp.windows.first(where: { $0.canBecomeMain })?.orderFrontRegardless()
                switch p.first {
                case "chat": shell.nav.select(.chat)
                case "account" where p.count > 1:
                    shell.nav.select(.account(p[1]))
                    if p.count > 2 { shell.nav.setSection(SectionID(p[2]), accountId: p[1]) }
                default: break
                }
                frames.reset(); _ = MainCPU.take()
                try? await Task.sleep(for: .seconds(1))
                print("BENCH place \(i) \(p.joined(separator: ":")): \(frames.summary), main cpu \(MainCPU.take()) ms")
                fflush(stdout)
                i += 1
                try? await Task.sleep(for: .seconds(max(0, pause - 1)))
            }
        }
        #endif
    }
}

#if DEBUG
/// The main thread's CPU time since the last call, in ms (read on the main thread).
@MainActor
enum MainCPU {
    private static var last: Double = 0
    static func take() -> Int {
        var t = timespec(); clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
        let now = Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1_000_000
        defer { last = now }
        return Int(now - last)
    }
}

/// Synthetic mouse moves over the main window, for measuring what hovering costs.
@MainActor
enum MouseSweep {
    private static var timer: Timer?
    private static var step = 0
    static func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }), let view = w.contentView else { return }
                step += 1
                let size = view.bounds.size
                let x = 80 + CGFloat(step * 7 % Int(max(size.width - 160, 1)))
                let y = 80 + CGFloat(step * 3 % Int(max(size.height - 160, 1)))
                guard let e = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: x, y: y), modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: 0, pressure: 0) else { return }
                w.sendEvent(e)
            }
        }
    }
}
#endif

#if DEBUG
/// `WN_DEMO_CHAT_SCROLL=<points per second>` (with `WN_DEMO_CHAT_CYCLE` opening a long chat): the message list scrolls up
/// for three seconds, then down for three, again and again, at that speed (600 is a slow read, 3000 a flick), stepped by
/// the display link as a real scroll is. Each second it prints the frames drawn, the late ones and the main thread's CPU
/// time - the cost of scrolling a chat, measured without a hand on the mouse. `WN_DEMO_CHAT_SCROLL_UP=<seconds>`: it only
/// scrolls up, for that long, then leaves the list alone (still printing where it is) - to try the jump-to-latest button.
@MainActor
final class ChatScrollBench: NSObject {
    static let shared = ChatScrollBench()
    private var link: CADisplayLink?
    private var speed: CGFloat = 0
    private var began: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var second = 0
    private var gaps: [CFTimeInterval] = []
    private weak var found: NSScrollView?
    private var carry: CGFloat = 0
    private let upOnly = ProcessInfo.processInfo.environment["WN_DEMO_CHAT_SCROLL_UP"].flatMap(Double.init)

    static func start() {
        guard let speed = ProcessInfo.processInfo.environment["WN_DEMO_CHAT_SCROLL"].flatMap(Double.init), speed > 0 else { return }
        shared.speed = CGFloat(speed)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(7))
            shared.census()
            guard let screen = NSScreen.main else { return }
            let l = screen.displayLink(target: shared, selector: #selector(step(_:)))
            l.add(to: .main, forMode: .common)
            shared.link = l
        }
    }

    /// How many AppKit views the main window holds, by class: AppKit walks them all on every layout pass.
    private func census() {
        guard let root = NSApp.windows.first(where: { $0.canBecomeMain })?.contentView else { return }
        var count: [String: Int] = [:], total = 0
        func walk(_ v: NSView) { total += 1; count[String(describing: type(of: v)), default: 0] += 1; v.subviews.forEach(walk) }
        walk(root)
        let top = count.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        print("BENCH views \(total): \(top)"); fflush(stdout)
    }

    /// The tallest vertical scroll view in the main window: the message list. Trying the jump button, the one under the
    /// middle of the chat instead (a chat a page or two long is shorter than the list of chats beside it).
    private var list: NSScrollView? {
        guard let root = NSApp.windows.first(where: { $0.canBecomeMain })?.contentView else { return nil }
        if upOnly != nil {
            var v = root.hitTest(NSPoint(x: root.bounds.width * 0.65, y: root.bounds.midY))
            while let cur = v { if let s = cur as? NSScrollView { return s }; v = cur.superview }
        }
        var best: NSScrollView?
        func walk(_ v: NSView) {
            if let s = v as? NSScrollView, let doc = s.documentView, doc.frame.height > s.contentView.bounds.height * 2,
               doc.frame.height > (best?.documentView?.frame.height ?? 0) { best = s }
            v.subviews.forEach(walk)
        }
        walk(root)
        return best
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        if began == 0 { began = now; last = now; _ = MainCPU.take(); return }
        let dt = now - last
        gaps.append(dt); last = now
        if found == nil { found = list; NSApp.windows.first(where: { $0.canBecomeMain })?.orderFrontRegardless() }
        if let s = found {
            let up = upOnly != nil || Int((now - began) / 3) % 2 == 0
            // A real wheel event, handled as one from the mouse is (setting the clip view's origin instead was undone by
            // the scroll view's own state): pixels, positive scrolls toward older messages.
            if upOnly.map({ now - began < $0 }) ?? true { carry += (up ? 1 : -1) * speed * CGFloat(dt) }
            let whole = carry.rounded(.towardZero); carry -= whole
            if whole != 0, let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(whole), wheel2: 0, wheel3: 0),
               let event = NSEvent(cgEvent: cg) {
                s.scrollWheel(with: event)
            }
        }
        let s = Int(now - began)
        if s > second {
            second = s
            let frame = link.duration > 0 ? link.duration : 1.0 / 60
            let late = gaps.map { $0 - frame }
            let worst = Int(((late.max() ?? 0) * 1000).rounded())
            let over33 = late.filter { $0 >= 0.017 }.count, over50 = late.filter { $0 >= 0.05 }.count
            let y = Int(found?.contentView.bounds.origin.y ?? -1), h = Int(found?.documentView?.frame.height ?? -1)
            print("BENCH scroll \(s): \(gaps.count) frames, \(over33) late ≥17 ms, \(over50) late ≥50 ms, worst \(worst) ms, main cpu \(MainCPU.take()) ms, y \(y) of \(h), view \(Int(found?.contentView.bounds.height ?? -1))")
            fflush(stdout)
            gaps = []
            // Trying a position: the list is looked up again each second, so it is the one of the chat now open.
            if upOnly != nil { found = nil }
        }
    }
}
#endif

#if DEBUG
/// `WN_DEMO_MENULOG=1`: prints when a menu starts and ends tracking and when the app's main menu is replaced or changed,
/// to find what closes a pop-up menu that nobody clicked away.
@MainActor
enum MenuLog {
    private static var observers: [NSObjectProtocol] = []
    private static var timer: Timer?
    private static var lastMain: ObjectIdentifier?
    private static let t0 = ProcessInfo.processInfo.systemUptime
    private static func stamp() -> String { String(format: "%.2f", ProcessInfo.processInfo.systemUptime - t0) }

    static func start() {
        guard ProcessInfo.processInfo.environment["WN_DEMO_MENULOG"] == "1" else { return }
        if ProcessInfo.processInfo.environment["WN_DEMO_ACTIVATE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }
        }
        let c = NotificationCenter.default
        func watch(_ name: Notification.Name, _ label: String) {
            observers.append(c.addObserver(forName: name, object: nil, queue: nil) { n in
                let menu = n.object as? NSMenu
                let main = MainActor.assumeIsolated { menu === NSApp.mainMenu || menu?.supermenu != nil }
                print("MENULOG \(MainActor.assumeIsolated { stamp() }) \(label) \(main ? "main-menu" : "popup") '\(menu?.title ?? "")' items=\(menu?.numberOfItems ?? -1)")
                if label == "begin", !main, let menu {
                    print("MENULOG items: " + menu.items.prefix(6).map { $0.isSeparatorItem ? "-" : $0.title }.joined(separator: " | "))
                    // Closed again by itself, so the next scripted click can run.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { menu.cancelTracking() }
                }
                fflush(stdout)
                if label == "end", !main {
                    for line in Thread.callStackSymbols.prefix(40) { print("MENUSTACK " + line) }
                    fflush(stdout)
                }
            })
        }
        for (name, label) in [(NSApplication.didResignActiveNotification, "app resign active"), (NSApplication.didBecomeActiveNotification, "app active"),
                              (NSWindow.didBecomeKeyNotification, "window key"), (NSWindow.didResignKeyNotification, "window resign key"),
                              (NSWindow.didBecomeMainNotification, "window main"), (NSWindow.didResignMainNotification, "window resign main")] {
            observers.append(c.addObserver(forName: name, object: nil, queue: nil) { n in
                print("MENULOG \(MainActor.assumeIsolated { stamp() }) \(label) \(n.object.map { String(describing: type(of: $0)) } ?? "")"); fflush(stdout)
            })
        }
        watch(NSMenu.didBeginTrackingNotification, "begin")
        watch(NSMenu.didEndTrackingNotification, "end")
        watch(NSMenu.didAddItemNotification, "addItem")
        watch(NSMenu.didRemoveItemNotification, "removeItem")
        watch(NSMenu.didChangeItemNotification, "changeItem")
        let t = Timer(timeInterval: 0.01, repeats: true) { _ in
            MainActor.assumeIsolated {
                let id = NSApp.mainMenu.map(ObjectIdentifier.init)
                if id != lastMain { lastMain = id; print("MENULOG \(stamp()) mainMenu REPLACED"); fflush(stdout) }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// `WN_DEMO_CLICK=x,y[;x,y…]` (window points from its top-left): clicks there in turn, 2.5 s apart, as the mouse would
    /// (the events go through the window's own hit-testing, title bar included).
    static func clicks() {
        guard let spec = ProcessInfo.processInfo.environment["WN_DEMO_CLICK"] else { return }
        // `r:x,y` is a right-click (the pointer moved there first); `R:x,y` a right-click where the pointer already is.
        let points = spec.split(separator: ";").compactMap { raw -> (NSPoint, Bool, Bool)? in
            let right = raw.hasPrefix("r:") || raw.hasPrefix("R:"), still = raw.hasPrefix("R:")
            let v = (right ? raw.dropFirst(2) : raw[...]).split(separator: ",").compactMap { Double($0) }
            return v.count == 2 ? (NSPoint(x: v[0], y: v[1]), right, still) : nil
        }
        for (i, (p, right, still)) in points.enumerated() {
            let t = Timer(timeInterval: 9 + Double(i) * 2.5, repeats: false) { _ in
                MainActor.assumeIsolated {
                    guard let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) else { return }
                    let at = NSPoint(x: p.x, y: w.frame.height - p.y)
                    if right {
                        // A right-click as a hand makes it: the pointer comes over the place first, then the button.
                        print("MENULOG \(stamp()) right-click \(Int(p.x)),\(Int(p.y))"); fflush(stdout)
                        if !still, let move = NSEvent.mouseEvent(with: .mouseMoved, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) { NSApp.postEvent(move, atStart: false) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
                                if let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .rightMouseDown ? 1 : 0) {
                                    NSApp.postEvent(e, atStart: false)
                                }
                            }
                        }
                        return
                    }
                    // Which AppKit view is under the click, with its ancestors: says who takes it when SwiftUI's own view does not.
                    var chain: [String] = [], under = w.contentView?.superview?.hitTest(at)
                    while let v = under, chain.count < 6 {
                        // A scroll view with where it is in the window, to tell one list from another.
                        let frame = v is NSScrollView ? " \(v.convert(v.bounds, to: nil).integral)" : ""
                        chain.append(String(describing: type(of: v)).prefix(48).description + frame); under = v.superview
                    }
                    print("MENULOG \(stamp()) click \(Int(p.x)),\(Int(p.y)) active=\(NSApp.isActive) key=\(w.isKeyWindow) under=\(chain.joined(separator: " < "))"); fflush(stdout)
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                            NSApp.sendEvent(e)
                        }
                    }
                }
            }
            RunLoop.main.add(t, forMode: .common)
        }
    }
}
#endif
