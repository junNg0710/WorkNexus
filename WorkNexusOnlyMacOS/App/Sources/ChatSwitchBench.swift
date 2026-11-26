import AppKit
import Foundation
import QuartzCore

/// DEBUG builds only: `WN_DEMO_CHAT_CYCLE=<accountId>:<gid>,<gid>,…` opens those chats in turn, one every
/// `WN_DEMO_CHAT_CYCLE_SECONDS` (default 3), so the cost of switching conversations can be measured on a copied database
/// without anyone clicking. After each switch it prints the longest gap between screen frames in the next second (what
/// the performance log calls a late frame), whether or not the app is in front.
enum ChatSwitchBench {
    @MainActor
    static func start(chat: ChatWiring) {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let spec = env["WN_DEMO_CHAT_CYCLE"], let colon = spec.firstIndex(of: ":") else { return }
        let accountId = String(spec[..<colon])
        let gids = spec[spec.index(after: colon)...].split(separator: ",").map(String.init)
        let pause = env["WN_DEMO_CHAT_CYCLE_SECONDS"].flatMap(Double.init) ?? 3
        guard !gids.isEmpty else { return }
        // `WN_DEMO_CHAT_CYCLE_COUNT=<n>`: stops after n switches, leaving those chats kept and the last one open.
        let count = env["WN_DEMO_CHAT_CYCLE_COUNT"].flatMap(Int.init) ?? Int.max
        let frames = FrameGaps()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            var i = 0
            while !Task.isCancelled, i < count {
                // The first opens the Chat place on the account; then only the chat changes, as a click in the list does.
                if i == 0 { chat.show(accountId: accountId, chatGid: gids[0]) } else { chat.events.open(chatGid: gids[i % gids.count]) }
                frames.reset()
                _ = MainCPU.take()
                try? await Task.sleep(for: .seconds(1))
                // The main thread's CPU time is steadier than frame gaps on a loaded machine: it is the work the switch cost.
                print("BENCH switch \(i) to \(gids[i % gids.count].prefix(8)): main \(MainCPU.take()) ms, \(frames.summary)")
                fflush(stdout)
                i += 1
                try? await Task.sleep(for: .seconds(max(0, pause - 1)))
            }
        }
        #endif
    }
}

#if DEBUG
/// Gaps between display frames since the last `reset`.
@MainActor
final class FrameGaps: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private var gaps: [CFTimeInterval] = []
    private var frame: CFTimeInterval = 1.0 / 60

    override init() {
        super.init()
        guard let screen = NSScreen.main else { return }
        let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// Keeps the time of the last frame: the gap that spans what the caller is about to do (or just did) is the one
    /// that matters most, and starting over from nothing left it out of every count.
    func reset() { gaps = [] }

    @objc private func tick(_ l: CADisplayLink) {
        if let last { gaps.append(l.timestamp - last) }
        last = l.timestamp
        if l.duration > 0 { frame = l.duration }
    }

    var summary: String {
        let late = gaps.map { $0 - frame }
        let worst = Int(((late.max() ?? 0) * 1000).rounded())
        let over = late.filter { $0 >= 0.05 }.count, over16 = late.filter { $0 >= 0.016 }.count
        let order = late.filter { $0 >= 0.008 }.map { String(Int(($0 * 1000).rounded())) }.joined(separator: ",")
        return "worst late \(worst) ms, \(over) late ≥50 ms, \(over16) late ≥16 ms, \(gaps.count) frames [\(order)]"
    }
}
#endif
