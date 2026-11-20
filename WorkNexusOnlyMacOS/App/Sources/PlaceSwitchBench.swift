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
