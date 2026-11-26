/// Not in the Flutter app.
import Foundation

/// What a macOS crash report (`.ips`) says, in the few lines the diagnostics log keeps.
///
/// macOS writes one for every crash (`~/Library/Logs/DiagnosticReports`), but the app's own log only knew that its last
/// session "ended without quitting": a log sent in by a user could not tell a crash from a forced quit, nor what crashed.
public struct CrashReportSummary: Equatable, Sendable {
    /// The app and version the report is about: "WorkNexusMac 1.9.37 (58)".
    public var app: String
    /// When it was captured, as the report writes it.
    public var time: String
    /// The exception: "EXC_BREAKPOINT (SIGTRAP), codes 0x0000000000000001, 0x00000001a2b3c4d5".
    public var exception: String
    /// Why the process was ended: "SIGNAL 5 Trace/BPT trap: 5".
    public var termination: String
    /// What the runtime said as it died ("Fatal error: Index out of range").
    public var messages: [String]
    /// The thread that crashed: "thread 0 (com.apple.main-thread)".
    public var thread: String
    /// Its top frames, innermost first: "WorkNexusMac  closure #1 in Foo.bar() + 124", or an offset for a stripped image.
    public var frames: [String]

    /// How many of the crashed thread's innermost frames are kept, and how many of the app's own below those.
    static let topFrames = 10
    static let ownFrames = 5

    /// Reads a report: a line of JSON (the header), then the JSON body. Nil for anything else (an old plain-text report).
    public static func parse(_ text: String) -> CrashReportSummary? {
        guard let split = text.firstIndex(of: "\n"),
              let header = json(String(text[..<split])), let body = json(String(text[text.index(after: split)...])) else { return nil }
        let process = body["procName"] as? String ?? header["app_name"] as? String ?? header["name"] as? String ?? "?"
        let bundle = body["bundleInfo"] as? [String: Any] ?? [:]
        let filled = { (text: String?) in text.flatMap { $0.isEmpty ? nil : $0 } }
        let version = filled(bundle["CFBundleShortVersionString"] as? String ?? header["app_version"] as? String)
        let build = filled(bundle["CFBundleVersion"] as? String ?? header["build_version"] as? String)
        let app = ([process, version].compactMap { $0 } + (build.map { ["(\($0))"] } ?? [])).joined(separator: " ")

        let exc = body["exception"] as? [String: Any] ?? [:]
        var exception = exc["type"] as? String ?? "unknown exception"
        if let signal = exc["signal"] as? String { exception += " (\(signal))" }
        if let subtype = exc["subtype"] as? String { exception += ", \(subtype)" }
        if let codes = exc["codes"] as? String, !codes.isEmpty { exception += ", codes \(codes)" }

        let term = body["termination"] as? [String: Any] ?? [:]
        var parts = [term["namespace"] as? String, (term["code"] as? NSNumber).map { "\($0)" }, term["indicator"] as? String].compactMap { $0 }
        if let by = term["byProc"] as? String { parts.append("by \(by)") }
        parts += term["reasons"] as? [String] ?? []

        let asi = body["asi"] as? [String: Any] ?? [:]
        let messages = asi.keys.sorted().flatMap { asi[$0] as? [String] ?? [] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        let threads = body["threads"] as? [[String: Any]] ?? []
        let index = (body["faultingThread"] as? NSNumber)?.intValue ?? threads.firstIndex { $0["triggered"] as? Bool == true } ?? 0
        let crashed = threads.indices.contains(index) ? threads[index] : [:]
        let label = (crashed["queue"] as? String) ?? (crashed["name"] as? String)
        let images = (body["usedImages"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "?" }
        let all = (crashed["frames"] as? [[String: Any]] ?? []).map { frame -> (image: String, line: String) in
            let image = (frame["imageIndex"] as? NSNumber).flatMap { images.indices.contains($0.intValue) ? images[$0.intValue] : nil } ?? "?"
            if let symbol = frame["symbol"] as? String {
                return (image, "\(image)  \(symbol) + \((frame["symbolLocation"] as? NSNumber)?.intValue ?? 0)")
            }
            return (image, "\(image) + 0x" + String((frame["imageOffset"] as? NSNumber)?.uint64Value ?? 0, radix: 16))
        }
        var frames = all.prefix(topFrames).map(\.line)
        // The app's own code further down: what led into the system frames on top.
        let below = all.dropFirst(topFrames).filter { $0.image == process }.prefix(ownFrames)
        frames += below.map { "… " + $0.line }

        return CrashReportSummary(app: app, time: body["captureTime"] as? String ?? header["timestamp"] as? String ?? "?",
                                  exception: exception, termination: parts.joined(separator: " "), messages: messages,
                                  thread: "thread \(index)" + (label.map { " (\($0))" } ?? ""), frames: frames)
    }

    /// The summary as log lines.
    public var lines: [String] {
        var out = ["\(app) crashed at \(time): \(exception)" + (termination.isEmpty ? "" : " — \(termination)")]
        out += messages.map { "  said: \($0)" }
        if !frames.isEmpty { out.append("  crashed \(thread):"); out += frames.map { "    \($0)" } }
        return out
    }

    private static func json(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}

/// The reports macOS keeps about this app's abnormal ends.
public enum CrashReports {
    /// Where macOS writes them for this user (the newest, and the ones it has already sent to Apple).
    public static var defaultDirectories: [URL] {
        let reports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        return [reports, reports.appendingPathComponent("Retired", isDirectory: true)]
    }

    static let crashKinds: Set<String> = ["ips", "crash"]
    /// A hang, a spin (stuck with a busy CPU) or a resource report: no crash, but a reason for a forced quit.
    static let otherKinds: Set<String> = ["hang", "spin", "diag"]

    /// The reports about `process` written since `since`, newest first.
    public static func find(process: String, since: Date, in directories: [URL] = defaultDirectories) -> [URL] {
        let fm = FileManager.default
        var found: [(url: URL, at: Date)] = []
        for directory in directories {
            let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.lastPathComponent.hasPrefix(process)
                && (crashKinds.contains(file.pathExtension) || otherKinds.contains(file.pathExtension)) {
                let at = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if at >= since { found.append((file, at)) }
            }
        }
        return found.sorted { $0.at > $1.at }.map(\.url)
    }

    /// What the log says about a session of `process` that ended without quitting after `since`: the crash macOS
    /// recorded, or that it recorded none.
    public static func describeEnd(process: String, since: Date, in directories: [URL] = defaultDirectories) -> [String] {
        let reports = find(process: process, since: since, in: directories)
        guard !reports.isEmpty else {
            // (Not "…session: it was…": the log masks what follows "session:" as a secret.)
            return ["macOS wrote no crash report for the session that never quit, so it was a forced quit, the system ending the app, or a restart - not a crash"]
        }
        var lines: [String] = []
        // The newest two: one crash can leave a second report behind (a crash while it was being handled).
        for report in reports.filter({ crashKinds.contains($0.pathExtension) }).prefix(2) {
            let text = (try? String(contentsOf: report, encoding: .utf8)) ?? ""
            if let summary = CrashReportSummary.parse(text) {
                lines += summary.lines
                lines.append("  full report: \(report.lastPathComponent)")
            } else {
                lines.append("A crash report that could not be read: \(report.lastPathComponent)")
            }
        }
        for report in reports where otherKinds.contains(report.pathExtension) {
            lines.append("macOS also noted the app not responding or overusing the Mac: \(report.lastPathComponent)")
        }
        return lines
    }
}
