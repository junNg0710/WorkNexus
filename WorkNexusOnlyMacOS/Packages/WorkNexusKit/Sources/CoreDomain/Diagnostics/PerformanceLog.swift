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
    }
    private static let state = State()
    /// The area of its entries in the log.
    public static let area = "perf"

    public static var isEnabled: Bool { state.lock.withLock { state.enabled } }
    public static func setEnabled(_ on: Bool) {
        state.lock.withLock { state.enabled = on }
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
        let started = Date()
        let value = try await work()
        report(name, Date().timeIntervalSince(started), slowerThan)
        return value
    }

    /// `measure` for synchronous work.
    public static func measureSync<T>(_ name: String, slowerThan: TimeInterval = 0.016, _ work: () throws -> T) rethrows -> T {
        guard isEnabled else { return try work() }
        let started = Date()
        let value = try work()
        report(name, Date().timeIntervalSince(started), slowerThan)
        return value
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

    public init() {}

    /// One frame drawn `gap` seconds after the previous, at a display interval of `frame`, at time `now`. Returns a line
    /// to write when a window closes (or a hang happened).
    public mutating func add(gap: TimeInterval, frame: TimeInterval, now: TimeInterval) -> String? {
        frames += 1
        let late = gap - frame
        var out: String?
        if late >= Self.hangAfter {
            out = "Not responding for \(Self.ms(late))"
        } else if late >= Self.lateAfter {
            if started == nil { started = now }
            count += 1; worst = max(worst, late); lost += late
        }
        if let s = started, now - s >= Self.span { out = [out, close()].compactMap { $0 }.joined(separator: "; ") }
        return out
    }

    /// The line for what was gathered, and a fresh window; nil when nothing was late.
    public mutating func close() -> String? {
        defer { self = FrameStutterWindow() }
        guard count > 0 else { return nil }
        return "Stutter: \(count) late frame\(count == 1 ? "" : "s") in \(Int(Self.span)) s, worst \(Self.ms(worst)), \(Self.ms(lost)) lost"
    }

    static func ms(_ t: TimeInterval) -> String { "\(Int((t * 1000).rounded())) ms" }
}
