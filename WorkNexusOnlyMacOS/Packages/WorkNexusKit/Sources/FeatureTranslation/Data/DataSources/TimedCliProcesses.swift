import Foundation

/// How long a killed CLI's output pipes get to close before the run stops waiting for them.
private let killedOutputGrace: TimeInterval = 1

/// What one CLI run left behind.
struct CliRun { var exitCode: Int32; var stdout: String; var stderr: String; var timedOut: Bool }

/// Ported from: lib/features/translation/data/opencode_translation_service.dart (`_run`, the process bookkeeping)
/// Runs AI CLIs (OpenCode, Claude Code) under a deadline, by key, so a run can be cancelled. Foundation's one-shot APIs
/// have no deadline, so the process is driven here and killed — with whatever it started — when the timer fires;
/// otherwise a stalled CLI hangs the caller forever.
final class TimedCliProcesses: @unchecked Sendable {
    private let runner: CliRunner

    /// In-flight CLI processes by key, so `cancel` can kill one; plus processes that were killed (timeout or cancel),
    /// whose run then stops waiting on the pipes. Tracked here, not inferred from `running`: a new run of the same key
    /// may have taken its entry by then.
    private struct State { var running: [String: Process] = [:]; var killed: Set<ObjectIdentifier> = []; var timedOut: Set<ObjectIdentifier> = [] }
    private let state = Locked(State())

    init(runner: CliRunner) { self.runner = runner }

    func cancel(_ key: String) async {
        let process: Process? = state.withLock { s in
            guard let p = s.running.removeValue(forKey: key) else { return nil }
            s.killed.insert(ObjectIdentifier(p)); return p
        }
        if let process { await runner.killTree(process) }
    }

    /// Spawns `path args…` in `directory` and collects its output; nil when it could not start.
    func run(key: String, path: String, args: [String], directory: String, timeout: TimeInterval) async -> CliRun? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err
        // Nothing is piped in; an open stdin makes CLIs that read piped input block until EOF.
        process.standardInput = FileHandle.nullDevice
        let stdout = PipeCapture(out), stderr = PipeCapture(err)

        let started = Locked(false)
        let id = ObjectIdentifier(process)
        // The deadline: kill the tree, and remember that it was us.
        let deadline = DispatchWorkItem { [weak self, weak process] in
            guard let self, let process, process.isRunning else { return }
            self.state.withLock { _ = $0.killed.insert(id); _ = $0.timedOut.insert(id) }
            Task { await self.runner.killTree(process) }
        }
        let exit: Int32 = await withCheckedContinuation { cont in
            process.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            state.withLock { $0.running[key] = process }
            do { try process.run() } catch {
                state.withLock { if $0.running[key] === process { $0.running[key] = nil } }
                cont.resume(returning: -1)
                return
            }
            started.withLock { $0 = true }
            // The child owns the write ends now; holding ours open would keep the pipes from ever reaching EOF.
            try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        }
        deadline.cancel()
        guard started.withLock({ $0 }) else { return nil }

        let (wasKilled, didTimeOut) = state.withLock { s -> (Bool, Bool) in
            let k = s.killed.remove(id) != nil, t = s.timedOut.remove(id) != nil
            if s.running[key] === process { s.running[key] = nil }   // a newer run of the same key may have taken it: leave it
            return (k, t)
        }
        // A child that outlives the CLI can hold the pipes open for as long as it lives: a killed run takes what has
        // arrived and stops waiting; a run that ended by itself waits for them to close.
        let grace: TimeInterval? = wasKilled ? killedOutputGrace : nil
        async let o = stdout.text(within: grace)
        async let e = stderr.text(within: grace)
        let (so, se) = await (o, e)
        return CliRun(exitCode: exit, stdout: so, stderr: se, timedOut: didTimeOut)
    }
}

/// Terminal styling (colour/bold) CLIs write around their own messages.
private let ansiEscape = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[a-zA-Z]")
func stripAnsi(_ s: String) -> String {
    ansiEscape.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
}

/// The last few lines of CLI output — enough to explain a failure without dumping a whole transcript into a toast. The
/// escape codes are stripped: the UI shows plain text instead of `^[[91m^[[1mError:`.
func cliTail(_ output: String, lines: Int = 4, maxChars: Int = 400) -> String {
    let kept = stripAnsi(output).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let joined = kept.suffix(lines).joined(separator: " · ")
    return joined.count <= maxChars ? joined : String(joined.prefix(maxChars)) + "…"
}

func firstNonEmpty(_ a: String?, _ b: String?) -> String? {
    if let first = a?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty { return first }
    if let second = b?.trimmingCharacters(in: .whitespacesAndNewlines), !second.isEmpty { return second }
    return nil
}
