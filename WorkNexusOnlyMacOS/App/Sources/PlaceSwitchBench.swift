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
                switch p.first {
                case "chat": shell.nav.select(.chat)
                case "account" where p.count > 1:
                    shell.nav.select(.account(p[1]))
                    if p.count > 2 { shell.nav.setSection(SectionID(p[2]), accountId: p[1]) }
                default: break
                }
                frames.reset()
                try? await Task.sleep(for: .seconds(1))
                print("BENCH place \(i) \(p.joined(separator: ":")): \(frames.summary)")
                fflush(stdout)
                i += 1
                try? await Task.sleep(for: .seconds(max(0, pause - 1)))
            }
        }
        #endif
    }
}
