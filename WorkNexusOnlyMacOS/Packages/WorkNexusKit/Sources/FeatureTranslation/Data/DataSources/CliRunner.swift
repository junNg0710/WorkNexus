import Foundation

/// Ported from: lib/features/translation/data/datasources/cli_runner.dart (macOS branch)
/// Resolves CLI binaries (GUI apps don't inherit the shell PATH) and spawns them. One instance is shared through the
/// composition root, so a binary is looked up once per session. Environment, process launcher and file check are
/// injectable so lookup is testable.
public final class CliRunner: @unchecked Sendable {
    /// Runs a short command to completion and returns its stdout; nil on failure.
    public typealias RunProcess = @Sendable (_ executable: String, _ args: [String]) async -> String?

    private let env: [String: String]
    private let run: RunProcess
    private let exists: @Sendable (String) -> Bool
    /// Binaries found so far, by name. Finding one spawns a login shell (which sources the user's whole profile) and
    /// that ran on every translation. A miss is looked up again, so a binary installed while the app runs is still
    /// found; a hit is checked to still exist, so one removed is not launched from a dead path.
    private let found = Locked<[String: String]>([:])

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, runProcess: RunProcess? = nil,
                fileExists: (@Sendable (String) -> Bool)? = nil) {
        env = environment
        run = runProcess ?? CliRunner.defaultRun
        exists = fileExists ?? { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func resolve(_ name: String, override: String? = nil) async -> String? {
        if let o = override?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty { return o }
        if let path = found.withLock({ $0[name] }), exists(path) { return path }
        guard let path = await resolveUnix(name) else { return nil }
        found.withLock { $0[name] = path }
        return path
    }

    /// A GUI launch omits the interactive-shell PATH (nvm, asdf, Homebrew, `~/.local/bin`, …), so ask a login shell,
    /// then fall back to a direct PATH scan.
    private func resolveUnix(_ name: String) async -> String? {
        let shell = env["SHELL"] ?? "/bin/zsh"
        if let out = await run(shell, ["-lic", "command -v \(name)"]) {
            let hits = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("/") }
            if let last = hits.last { return last }
        }
        return scanPath(name)
    }

    private func scanPath(_ name: String) -> String? {
        let dirs = (env["PATH"] ?? "").split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for dir in dirs { let c = "\(dir)/\(name)"; if exists(c) { return c } }
        return nil
    }

    /// Runs a short query (`zsh -lic "command -v …"`, `opencode models`) and returns its output once it exits. It does not
    /// wait for the output pipe to close: a login shell can start background jobs (version managers, prompt helpers) that
    /// inherit the pipe and keep it open long after the shell is gone, which used to hang the lookup forever. A query
    /// that is still running after `queryTimeout` is stopped.
    static let queryTimeout: TimeInterval = 20

    private static let defaultRun: RunProcess = { executable, args in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        let capture = PipeCapture(out)
        let started: Bool = await withCheckedContinuation { cont in
            p.terminationHandler = { _ in cont.resume(returning: true) }
            do { try p.run() } catch { p.terminationHandler = nil; cont.resume(returning: false); return }
            // The child owns the write end now; ours would keep the pipe from reaching EOF.
            try? out.fileHandleForWriting.close()
            DispatchQueue.global().asyncAfter(deadline: .now() + queryTimeout) { if p.isRunning { p.terminate() } }
        }
        guard started else { return nil }
        return await capture.text(within: 1)
    }

    /// Stops `process` and everything it started. `Process.terminate` ends only the process itself: the shell script
    /// around a binary would die while the real CLI behind it carries on — calling its model and using quota — with no
    /// one waiting for the answer.
    public func killTree(_ process: Process) async {
        // Children are listed before the parent goes: once it is gone they belong to launchd and can no longer be found through it.
        for pid in await descendants(of: process.processIdentifier).reversed() { kill(pid, SIGTERM) }
        if process.isRunning { process.terminate() }
    }

    /// The pids below `pid`, each parent before its children.
    func descendants(of pid: Int32) async -> [Int32] {
        guard let out = await run("/usr/bin/pgrep", ["-P", "\(pid)"]) else { return [] }
        var found: [Int32] = []
        for line in out.split(separator: "\n") {
            guard let child = Int32(line.trimmingCharacters(in: .whitespaces)) else { continue }
            found.append(child)
            found += await descendants(of: child)
        }
        return found
    }
}
