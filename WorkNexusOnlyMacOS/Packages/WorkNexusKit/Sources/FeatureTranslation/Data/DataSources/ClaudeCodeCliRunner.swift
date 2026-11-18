import Foundation

/// Not in the Flutter app.
/// Asks the installed Claude Code CLI whether it is signed in (`claude auth status --json`). Only `loggedIn` is read: the
/// account details it also prints (email, organization) are never kept. A signed-in answer is remembered for a few minutes,
/// since every AI run asks first.
public final class ClaudeCodeCliRunner: ClaudeCodeCli, @unchecked Sendable {
    private let runner: CliRunner
    private let processes: TimedCliProcesses
    private let binaryOverride: String?
    private let remember: TimeInterval
    private let now: @Sendable () -> Date
    private let lastSignedIn = Locked<Date?>(nil)

    public init(runner: CliRunner = CliRunner(), binaryOverride: String? = nil, remember: TimeInterval = 300,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.runner = runner; self.binaryOverride = binaryOverride; self.remember = remember; self.now = now
        processes = TimedCliProcesses(runner: runner)
    }

    public func status() async -> ClaudeCodeStatus {
        if let at = lastSignedIn.withLock({ $0 }), now().timeIntervalSince(at) < remember { return .loggedIn }
        guard let path = await runner.resolve("claude", override: binaryOverride) else { return .notInstalled }
        let run = await processes.run(key: "auth-status-\(UUID().uuidString)", path: path, args: ["auth", "status", "--json"],
                                      directory: NSHomeDirectory(), timeout: 15)
        let status = run.map { Self.status(fromAuthJson: $0.stdout) } ?? .loggedOut
        lastSignedIn.withLock { $0 = status == .loggedIn ? now() : nil }
        return status
    }

    static func status(fromAuthJson out: String) -> ClaudeCodeStatus {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] else { return .loggedOut }
        return json["loggedIn"] as? Bool == true ? .loggedIn : .loggedOut
    }
}
