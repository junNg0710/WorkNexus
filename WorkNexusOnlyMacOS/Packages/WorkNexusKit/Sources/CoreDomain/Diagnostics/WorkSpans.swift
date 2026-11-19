/// Not in the Flutter app.
import Foundation

/// The measured work the main thread did lately (`PerformanceLog.measureSync` on the main thread), kept so a late frame
/// or a hang can say what held the screen up, not only where it happened.
public struct WorkSpans: Sendable, Equatable {
    public struct Span: Sendable, Equatable {
        public var name: String
        public var start: TimeInterval
        public var end: TimeInterval
    }

    /// How many spans are kept (the oldest go first).
    public static let capacity = 256
    /// Shorter work is not kept: it cannot be what held a frame up.
    public static let minimum: TimeInterval = 0.002

    public private(set) var spans: [Span] = []

    public init() {}

    public mutating func add(_ name: String, start: TimeInterval, end: TimeInterval) {
        guard end - start >= Self.minimum else { return }
        spans.append(Span(name: name, start: start, end: end))
        if spans.count > Self.capacity { spans.removeFirst(spans.count - Self.capacity) }
    }

    /// The time each kind of work took between `from` and `to` (only the part inside that window).
    public func busy(from: TimeInterval, to: TimeInterval) -> [String: TimeInterval] {
        var out: [String: TimeInterval] = [:]
        for s in spans where s.end > from && s.start < to {
            out[s.name, default: 0] += min(s.end, to) - max(s.start, from)
        }
        return out
    }

    /// "busy with board: recompute 420 ms, zentao: build task board 120 ms, 260 ms unmeasured": the heaviest `limit`
    /// kinds of work, and how much of `late` no measured work explains. Nil when no measured work ran then.
    public static func describe(_ busy: [String: TimeInterval], late: TimeInterval, limit: Int = 4) -> String? {
        guard !busy.isEmpty else { return nil }
        let top = busy.sorted { $0.value > $1.value }.prefix(limit)
        var parts = top.map { "\($0.key) \(FrameStutterWindow.ms($0.value))" }
        let unmeasured = late - busy.values.reduce(0, +)
        if unmeasured >= FrameStutterWindow.lateAfter { parts.append("\(FrameStutterWindow.ms(unmeasured)) unmeasured") }
        return parts.isEmpty ? nil : "busy with " + parts.joined(separator: ", ")
    }
}

/// A user action waiting for the screen to show it: the time from the click (a place, a section, a ticket) to the next
/// frame drawn is how long the app took to answer it.
public struct PendingInteraction: Sendable, Equatable {
    public var name: String
    public var start: TimeInterval
    /// Answered later than this, the action is written down.
    public static let slowAfter: TimeInterval = 0.1
}
