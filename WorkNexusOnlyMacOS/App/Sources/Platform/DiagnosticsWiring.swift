import AppKit
import CoreDomain
import CoreTools
import CoreUI
import MetricKit

/// The diagnostics log at the composition root (not in the Flutter app): installs the file log, notes each launch and
/// quit (and a launch after a session that never quit), records uncaught exceptions and the crash and hang reports macOS
/// hands over through MetricKit, and keeps the user's last steps (the place on screen) for the next error.
@MainActor
final class DiagnosticsWiring: NSObject {
    let log: FileDiagnosticsLog
    private let marker: SessionMarker
    private var quitObserver: NSObjectProtocol?
    private var heartbeat: Timer?
    private var memory = MemoryLogPolicy()

    override init() {
        log = FileDiagnosticsLog(directory: PlatformPaths.applicationSupport().appendingPathComponent("Logs", isDirectory: true))
        Diagnostics.install(log)
        marker = SessionMarker(url: log.directory.appendingPathComponent(".running"))
        super.init()
        if let previous = marker.previous() {
            Diagnostics.warning("app", SessionMarker.describe(started: previous.started, lastSeen: previous.lastSeen))
            Self.explainEnd(of: previous.started)
        }
        marker.begin()
        Diagnostics.info("app", "Started · " + DiagnosticsArchive.about().replacingOccurrences(of: "\n", with: " · "))
        NSSetUncaughtExceptionHandler { exception in
            Diagnostics.error("crash", "Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")")
            Diagnostics.flush()
        }
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [marker] _ in
            Diagnostics.info("app", "Quit")
            Diagnostics.flush()
            marker.end()
        }
        // Every minute: the marker says the session is still alive, and the memory in use is noted when it is time.
        let beat = Timer(timeInterval: Self.heartbeatEvery, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.beat() } }
        beat.tolerance = Self.heartbeatEvery / 6
        RunLoop.main.add(beat, forMode: .common)
        heartbeat = beat
        MXMetricManager.shared.add(self)
        NetworkWatcher.shared.start()
        if Self.performanceLogOn { Self.setPerformanceLog(true) }
        if Self.showFpsOn { FpsMeter.shared.setOn(true) }
    }

    // MARK: How a session ended

    private static let heartbeatEvery: TimeInterval = 60
    /// How long after launch the crash report is looked for: macOS takes a few seconds to write one, and a user opens
    /// the app again at once.
    private static let reportDelay: Duration = .seconds(20)

    private func beat() {
        marker.touch()
        if let bytes = ProcessMemory.footprint(), let line = memory.line(bytes: bytes, now: Date()) { Diagnostics.info("app", line) }
    }

    /// Says in the log what macOS recorded about the session started at `started` that never quit: its crash report in
    /// short, or that there is none.
    private static func explainEnd(of started: Date) {
        let process = ProcessInfo.processInfo.processName
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: reportDelay)
            let lines = CrashReports.describeEnd(process: process, since: started)
            if lines.count > 1 { Diagnostics.error("crash", lines.joined(separator: "\n")) } else { Diagnostics.info("app", lines.joined()) }
            Diagnostics.flush()
        }
    }

    // MARK: FPS badge

    private static let fpsKey = "diagnostics.showFps"

    /// Whether the user turned the FPS badge on (Settings › Local data › Diagnostics); kept on this Mac.
    static var showFpsOn: Bool { UserDefaults.standard.bool(forKey: fpsKey) }

    static func setShowFps(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: fpsKey)
        FpsMeter.shared.setOn(on)
    }

    // MARK: Performance log

    private static let performanceKey = "diagnostics.performanceLog"

    /// Whether the user turned the performance log on (Settings › Local data › Diagnostics); kept on this Mac.
    static var performanceLogOn: Bool { UserDefaults.standard.bool(forKey: performanceKey) }

    /// Turns the performance log on or off: slow work and screen stutters are written to the log only while it is on.
    static func setPerformanceLog(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: performanceKey)
        PerformanceLog.setEnabled(on)
        FrameStutterMonitor.shared.setRunning(on)
    }

    /// Keeps the place on screen as the user's steps (which part of the app, which ticket, the editor, a mini app).
    func follow(nav: AppNavController) {
        Diagnostics.step(Self.place(nav.state))
        observeChanges({ Self.place(nav.state) }) { Diagnostics.step($0) }
    }

    static func place(_ s: AppNavState) -> String {
        var parts = [s.rail.key]
        if case .account(let id) = s.rail, let loc = s.locations[id] { parts.append(loc.section.rawValue + (loc.scopeId.map { " #\($0)" } ?? "")) }
        if case .settings = s.rail { parts.append(s.settingsSection) }
        if case .workspace = s.rail { parts.append(s.workspaceSection) }
        if let ticket = s.ticketHistories[s.rail.key]?.last { parts.append("ticket \(ticket)") }
        if let editor = s.editor { parts.append("editor \(String(describing: editor).prefix(60))") }
        if let app = s.miniAppId { parts.append("mini app \(app)") }
        return parts.joined(separator: " / ")
    }
}

extension DiagnosticsWiring: MXMetricManagerSubscriber {
    /// Crash and hang reports of earlier sessions, delivered by macOS on a later launch: a line each, and the full report
    /// (stack frames of the app's own code, no user data) beside the log.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let dir = PlatformPaths.applicationSupport().appendingPathComponent("Logs", isDirectory: true)
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let what = [crash.exceptionType.map { "exception \($0)" }, crash.signal.map { "signal \($0)" }, crash.terminationReason]
                    .compactMap { $0 }.joined(separator: ", ")
                Diagnostics.error("crash", "A crash in an earlier session (\(crash.applicationVersion)): \(what)")
            }
            for hang in payload.hangDiagnostics ?? [] {
                Diagnostics.warning("hang", "The app stopped responding for \(hang.hangDuration) in an earlier session")
            }
            let stamp = Int(payload.timeStampEnd.timeIntervalSince1970)
            try? payload.jsonRepresentation().write(to: dir.appendingPathComponent("metrickit-\(stamp).json"))
        }
        Diagnostics.flush()
    }
}
