/// Not in the Flutter app.
import Foundation

public enum DiagnosticLevel: String, Sendable { case info, warning, error }

/// One line of the diagnostics log: when, how bad, which part of the app, what happened (already redacted).
public struct DiagnosticEntry: Sendable, Equatable {
    public var date: Date
    public var level: DiagnosticLevel
    public var area: String
    public var message: String
    public init(date: Date, level: DiagnosticLevel, area: String, message: String) {
        self.date = date; self.level = level; self.area = area; self.message = message
    }
}

/// Where entries go (a file on this Mac); installed once by the composition root.
public protocol DiagnosticsSink: Sendable {
    /// `trail` is what the user did just before an error (empty for other entries).
    func write(_ entry: DiagnosticEntry, trail: [String])
    /// Waits until everything written so far is on disk (before a crash handler returns).
    func flush()
}

/// The app's diagnostics log: errors with the steps that led to them, kept on this Mac only, to trace what went wrong.
/// Any layer may report through it; nothing is recorded until a sink is installed. Every message is redacted
/// (`redact`): passwords, tokens, cookies and URL queries never reach the log.
public enum Diagnostics {
    /// How many of the user's last steps are kept for the next error.
    public static let trailLength = 30

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var sink: DiagnosticsSink?
        var trail: [String] = []
        var now: @Sendable () -> Date = Date.init
    }
    private static let state = State()

    public static func install(_ sink: DiagnosticsSink?, now: @escaping @Sendable () -> Date = Date.init) {
        state.lock.withLock { state.sink = sink; state.trail = []; state.now = now }
    }

    public static func error(_ area: String, _ message: String) { record(.error, area, message) }
    public static func warning(_ area: String, _ message: String) { record(.warning, area, message) }
    public static func info(_ area: String, _ message: String) { record(.info, area, message) }

    /// A step the user took (a place opened, a ticket shown): kept in memory and written only with the next error.
    public static func step(_ step: String) {
        let s = redact(step)
        state.lock.withLock {
            guard state.trail.last != s else { return }
            state.trail.append(s)
            if state.trail.count > trailLength { state.trail.removeFirst(state.trail.count - trailLength) }
        }
    }

    public static func flush() { state.lock.withLock { state.sink }?.flush() }

    private static func record(_ level: DiagnosticLevel, _ area: String, _ message: String) {
        let (sink, trail, date): (DiagnosticsSink?, [String], Date) = state.lock.withLock {
            let trail = level == .error ? state.trail : []
            // An error takes the steps before it; the next error gets only what happened after this one.
            if level == .error { state.trail = [] }
            return (state.sink, trail, state.now())
        }
        sink?.write(DiagnosticEntry(date: date, level: level, area: area, message: redact(message)), trail: trail)
    }

    // MARK: Network

    /// Records a request that did not succeed: an answer of 400 or more, or no answer at all. A refused sign-in (401,
    /// 403) and a server error (5xx) or a lost connection are errors; any other 4xx (a missing item) a warning. A request
    /// the app cancelled itself is not recorded. Successful requests are not recorded at all.
    public static func request(_ area: String, method: String, url: URL, status: Int?, error: Error? = nil, elapsed: TimeInterval) {
        if let error, isCancellation(error) { return }
        if let status, status < 400, error == nil { return }
        let what = describe(method: method, url: url), ms = Int(elapsed * 1000)
        if let status {
            let serious = status == 401 || status == 403 || status >= 500
            record(serious ? .error : .warning, area, "\(what) → HTTP \(status) (\(ms) ms)")
        } else {
            record(.error, area, "\(what) → \(error.map { String(describing: $0) } ?? "no answer") (\(ms) ms)")
        }
    }

    /// A request given up because nobody needed it any more (the user moved on): not a failure worth recording. Besides the
    /// system's own, a tool's error type says so with a `cancelled` case (`ZenTaoError.cancelled`, `Failure.cancelled`).
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let f = error as? Failure, case .cancelled = f { return true }
        if String(describing: error) == "cancelled" { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    // MARK: Redaction

    /// The longest message kept.
    public static let messageLimit = 2000

    private static let rules: [(NSRegularExpression, String)] = [
        // The query and fragment of every URL (ZenTao's classic pages carry the session id there).
        (#"(https?://[^\s?#"'<>]+)[?#][^\s"'<>]*"#, "$1?…"),
        (#"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer ***"),
        (#"(?i)\b(password|passwd|pwd|passcode|token|access_token|private[-_]token|secret|api[-_]?key|sid|zentaosid|session|cookie|authorization)(["']?\s*[:=]\s*["']?)(?!Bearer\b|\*\*\*)[^\s&"',;}]+"#, "$1$2***"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// `text` without secrets, on one line, at most `messageLimit` characters.
    public static func redact(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ⏎ ")
        for (rule, template) in rules {
            out = rule.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
        }
        return out.count > messageLimit ? String(out.prefix(messageLimit)) + "…" : out
    }

    /// A request as the log shows it: method, host and path, and of a ZenTao classic page only which module and function.
    public static func describe(method: String, url: URL) -> String {
        var place = "\(url.host ?? "")\(url.path)"
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let kept = items.filter { $0.name == "m" || $0.name == "f" }.map { "\($0.name)=\($0.value ?? "")" }
        if !kept.isEmpty { place += "?" + kept.joined(separator: "&") }
        return "\(method) \(place)"
    }
}
