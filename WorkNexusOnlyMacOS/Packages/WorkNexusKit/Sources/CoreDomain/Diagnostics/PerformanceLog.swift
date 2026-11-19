/// Not in the Flutter app.
import Foundation

/// The performance log: while the user has it on (Settings › Local data › Diagnostics), slow work and screen stutters
/// are written to the diagnostics log with where they happened, so lag can be traced from an exported log. Off, every
/// call returns at once and nothing is measured or kept.
public enum PerformanceLog {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var enabled = false
        var context: [String: String] = [:]
        var spans = WorkSpans()
        var interaction: PendingInteraction?
    }
    private static let state = State()
    /// The area of its entries in the log.
    public static let area = "perf"

    public static var isEnabled: Bool { state.lock.withLock { state.enabled } }
    public static func setEnabled(_ on: Bool) {
        state.lock.withLock { state.enabled = on; state.spans = WorkSpans(); state.interaction = nil }
        Diagnostics.info(area, on ? "Performance log on" : "Performance log off")
    }

    /// What is on screen, written with each entry (e.g. the kinds of chat rows in view) under `key`; nil removes it.
    /// Callers set it only while the log is on.
    public static func setContext(_ key: String, _ text: String?) {
        state.lock.withLock { state.context[key] = text }
    }

    /// The place on screen and what is on it.
    public static func whereNow() -> String {
        let details = state.lock.withLock { state.context.keys.sorted().compactMap { state.context[$0] } }.filter { !$0.isEmpty }
        return ([Diagnostics.place ?? "?"] + details).joined(separator: " · ")
    }

    /// Records `message` (with where it happened) while the log is on.
    public static func note(_ message: String) {
        guard isEnabled else { return }
        Diagnostics.info(area, "\(message) — \(whereNow())")
    }

    /// Times `work` and records it when it took `slowerThan` seconds or more.
    public static func measure<T>(_ name: String, slowerThan: TimeInterval = 0.05, _ work: () async throws -> T) async rethrows -> T {
        guard isEnabled else { return try await work() }
        let started = now()
        let value = try await work()
        report(name, now() - started, slowerThan)
        return value
    }

    /// `measure` for synchronous work. On the main thread it is also kept as what the main thread was busy with, so a late
    /// frame or a hang names it. `detail` (counts, sizes) is added to the written line only, so the same work adds up
    /// under one name.
    public static func measureSync<T>(_ name: @autoclosure () -> String, slowerThan: TimeInterval = 0.016,
                                      detail: @autoclosure () -> String = "", _ work: () throws -> T) rethrows -> T {
        guard isEnabled else { return try work() }
        let started = now()
        let value = try work()
        let ended = now(), label = name()
        if Thread.isMainThread { state.lock.withLock { state.spans.add(label, start: started, end: ended) } }
        let more = detail()
        report(more.isEmpty ? label : "\(label) (\(more))", ended - started, slowerThan)
        return value
    }

    /// The clock spans and frames are measured on (the display link's: seconds since the Mac started, not counting sleep).
    public static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// What the main thread was measured doing between `from` and `to`.
    public static func busy(from: TimeInterval, to: TimeInterval) -> [String: TimeInterval] {
        guard isEnabled else { return [:] }
        return state.lock.withLock { state.spans.busy(from: from, to: to) }
    }

    /// A user action starts (going to a place, opening a ticket): the next frame drawn says how long it took to answer.
    /// The first one waiting is kept — the click comes before the work it sets off.
    public static func beginInteraction(_ name: @autoclosure () -> String) {
        guard isEnabled else { return }
        let n = name(), t = now()
        state.lock.withLock { if state.interaction == nil { state.interaction = PendingInteraction(name: n, start: t) } }
    }

    /// A frame was drawn at `time` (the frame monitor): the action waiting is answered, and written down when it was slow.
    public static func frameShown(at time: TimeInterval) {
        guard isEnabled, let action = state.lock.withLock({ () -> PendingInteraction? in
            defer { state.interaction = nil }
            return state.interaction
        }) else { return }
        let took = time - action.start
        // Long past (the display link stopped while the app was in the background): not an answer to the click.
        guard took >= PendingInteraction.slowAfter, took < 30 else { return }
        let held = WorkSpans.describe(busy(from: action.start, to: time), late: took).map { ", \($0)" } ?? ""
        note("Slow: \(action.name) took \(Int((took * 1000).rounded())) ms to show\(held)")
    }

    private static func report(_ name: String, _ elapsed: TimeInterval, _ limit: TimeInterval) {
        guard elapsed >= limit else { return }
        note("Slow: \(name) took \(Int((elapsed * 1000).rounded())) ms")
    }
}

/// Late screen frames gathered over a short window, so a stuttering scroll makes one line, not one per frame.
public struct FrameStutterWindow: Sendable, Equatable {
    /// How long a window gathers before it is written.
    public static let span: TimeInterval = 5
    /// A frame is late when the main thread kept it at least this long past its time.
    public static let lateAfter: TimeInterval = 0.05
    /// Longer than this the app did not respond at all: written on its own.
    public static let hangAfter: TimeInterval = 1

    public private(set) var started: TimeInterval?
    public private(set) var count = 0
    public private(set) var worst: TimeInterval = 0
    public private(set) var lost: TimeInterval = 0
    public private(set) var frames = 0
    /// What the main thread was measured doing during the late frames, by kind of work.
    public private(set) var busy: [String: TimeInterval] = [:]

    public init() {}

    /// One frame drawn `gap` seconds after the previous, at a display interval of `frame`, at time `now`. Returns a line
    /// to write when a window closes (or a hang happened).
    /// `busy` is what the main thread was measured doing during that frame (`PerformanceLog.busy`).
    public mutating func add(gap: TimeInterval, frame: TimeInterval, now: TimeInterval, busy work: [String: TimeInterval] = [:]) -> String? {
        frames += 1
        let late = gap - frame
        var out: String?
        if late >= Self.hangAfter {
            out = "Not responding for \(Self.ms(late))" + (WorkSpans.describe(work, late: late).map { ", \($0)" } ?? "")
        } else if late >= Self.lateAfter {
            if started == nil { started = now }
            count += 1; worst = max(worst, late); lost += late
            busy.merge(work, uniquingKeysWith: +)
        }
        if let s = started, now - s >= Self.span { out = [out, close()].compactMap { $0 }.joined(separator: "; ") }
        return out
    }

    /// The line for what was gathered, and a fresh window; nil when nothing was late.
    public mutating func close() -> String? {
        defer { self = FrameStutterWindow() }
        guard count > 0 else { return nil }
        let line = "Stutter: \(count) late frame\(count == 1 ? "" : "s") in \(Int(Self.span)) s, worst \(Self.ms(worst)), \(Self.ms(lost)) lost"
        return line + (WorkSpans.describe(busy, late: lost).map { ", \($0)" } ?? "")
    }

    static func ms(_ t: TimeInterval) -> String { "\(Int((t * 1000).rounded())) ms" }
}
