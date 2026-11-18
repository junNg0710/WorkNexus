import CoreDomain
import Foundation

/// How long a single `opencode run` may take before we give up and kill it. The CLI has no timeout of its own: an
/// unauthenticated provider, a queued free-tier model or a stalled request can leave it running indefinitely.
public let openCodeTranslationTimeout: TimeInterval = 120

/// How long a killed CLI's output pipes get to close before the run stops waiting for them.
private let killedOutputGrace: TimeInterval = 1

/// Terminal styling (colour/bold) the CLI writes around its own messages.
private let ansiEscape = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[a-zA-Z]")
private func stripAnsi(_ s: String) -> String {
    ansiEscape.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
}

/// Ported from: lib/features/translation/data/opencode_translation_service.dart
/// Translation via the `opencode run` CLI. It uses OpenCode's **own** authentication (`opencode auth login`) and the
/// configured default model, so translations run through the user's normal provider and show up in its usage/quota. We
/// deliberately do NOT inject a provider API key into the environment — that would reroute the call onto a different
/// provider and bypass the user's OpenCode usage tracking.
public final class OpenCodeTranslationService: TranslationService, @unchecked Sendable {
    private let runner: CliRunner
    /// Fallback model id (`provider/model`) when a call doesn't pin one. nil ⇒ OpenCode's configured default.
    private let model: String?
    /// Directory the run is executed in. nil ⇒ the user's home.
    private let workingDir: String?
    private let binaryOverride: String?
    private let timeout: TimeInterval
    private static let templateVersion = "oc-v2"

    /// In-flight CLI processes by key, so `cancel` can kill one; plus processes that were killed (timeout or cancel),
    /// whose run then stops waiting on the pipes. Tracked here, not inferred from `running`: a new run of the same key
    /// may have taken its entry by then.
    private struct State { var running: [String: Process] = [:]; var killed: Set<ObjectIdentifier> = [] }
    private let state = Locked(State())

    public init(runner: CliRunner = CliRunner(), model: String? = nil, workingDir: String? = nil, binaryOverride: String? = nil,
                timeout: TimeInterval = openCodeTranslationTimeout) {
        self.runner = runner; self.model = model; self.workingDir = workingDir; self.binaryOverride = binaryOverride
        self.timeout = timeout
    }

    public func contentHash(_ source: TicketSource) -> String { FeatureTranslation.contentHash(source.title, source.body) }

    public func cancel(_ ticketId: String) async {
        let process: Process? = state.withLock { s in
            guard let p = s.running.removeValue(forKey: ticketId) else { return nil }
            s.killed.insert(ObjectIdentifier(p)); return p
        }
        if let process { await runner.killTree(process) }
    }

    public func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String,
                          model: String?) async -> Outcome<TranslationRecord> {
        guard let path = await runner.resolve("opencode", override: binaryOverride) else { return .failure(.agent("opencode not found on PATH")) }
        let language = translationLanguage(for: targetLang)
        let chosen = firstNonEmpty(model, self.model)
        let args = ["run"] + (chosen.map { ["-m", $0] } ?? []) + [ticketPrompt(source, language.englishName)]
        guard let run = await run(key: ticketId, path: path, args: args) else { return .failure(.agent("OpenCode translation failed: could not start")) }
        if run.timedOut {
            return .failure(.agent("OpenCode did not answer within \(Int(timeout))s and was stopped. Check `opencode run` in a terminal — the model may be unauthenticated or queued."))
        }
        if run.exitCode != 0 { return .failure(.agent(exitMessage(run))) }
        guard let parsed = extractTicketJson(run.stdout) else { return .failure(.parse(unparsableMessage(run))) }
        return .success(ticketRecord(parsed: parsed, ticketId: ticketId, source: source, sourceHash: sourceHash, lang: language.code,
                                     model: chosen ?? "opencode default", templateVersion: Self.templateVersion))
    }

    public func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation> {
        let language = translationLanguage(for: targetLang)
        return await complete(key: key, prompt: textPrompt(text, language.englishName), model: model)
    }

    public func complete(key: String, prompt: String, model: String?) async -> Outcome<TextTranslation> {
        guard let path = await runner.resolve("opencode", override: binaryOverride) else { return .failure(.agent("opencode not found on PATH")) }
        let chosen = firstNonEmpty(model, self.model)
        let args = ["run"] + (chosen.map { ["-m", $0] } ?? []) + [prompt]
        guard let run = await run(key: key, path: path, args: args) else { return .failure(.agent("OpenCode failed: could not start")) }
        if run.timedOut { return .failure(.agent("OpenCode did not answer within \(Int(timeout))s.")) }
        if run.exitCode != 0 { return .failure(.agent(exitMessage(run))) }
        let out = stripAnsi(run.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return .failure(.parse(unparsableMessage(run))) }
        return .success(TextTranslation(out, model: chosen))
    }

    struct CliRun { var exitCode: Int32; var stdout: String; var stderr: String; var timedOut: Bool }

    /// Spawns the CLI and collects its output under `timeout`. Foundation's one-shot APIs have no deadline, so we drive
    /// the process ourselves and kill it — with whatever it started — when the timer fires; otherwise a stalled CLI
    /// hangs the caller forever.
    private func run(key: String, path: String, args: [String]) async -> CliRun? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workingDir ?? NSHomeDirectory())
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
            self.state.withLock { _ = $0.killed.insert(id) }
            self.timedOut.withLock { _ = $0.insert(id) }
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

        let wasKilled = state.withLock { s -> Bool in
            let k = s.killed.contains(id)
            s.killed.remove(id)
            if s.running[key] === process { s.running[key] = nil }   // a newer run of the same key may have taken it: leave it
            return k
        }
        // A child that outlives the CLI can hold the pipes open for as long as it lives: a killed run takes what has
        // arrived and stops waiting; a run that ended by itself waits for them to close.
        let grace: TimeInterval? = wasKilled ? killedOutputGrace : nil
        async let o = stdout.text(within: grace)
        async let e = stderr.text(within: grace)
        let (so, se) = await (o, e)
        let didTimeOut = timedOut.withLock { $0.remove(id) != nil }
        return CliRun(exitCode: exit, stdout: so, stderr: se, timedOut: didTimeOut)
    }

    private let timedOut = Locked<Set<ObjectIdentifier>>([])

    /// The CLI reports provider/auth problems on stderr; surface that verbatim so "Token refresh failed: 401" reaches
    /// the user instead of a bare exit code.
    func exitMessage(_ run: CliRun) -> String {
        let detail = firstNonEmpty(run.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                                   run.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        return detail.map { "OpenCode exited \(run.exitCode): \(tail($0))" } ?? "OpenCode exited \(run.exitCode)"
    }

    func unparsableMessage(_ run: CliRun) -> String {
        let detail = firstNonEmpty(run.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                                   run.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        return detail.map { "Could not parse OpenCode translation: \(tail($0))" } ?? "OpenCode returned nothing to translate"
    }

    /// The last few lines of CLI output — enough to explain the failure without dumping a whole transcript into a
    /// snackbar. The escape codes are stripped: the UI shows plain text instead of `^[[91m^[[1mError:`.
    func tail(_ output: String, lines: Int = 4, maxChars: Int = 400) -> String {
        let kept = stripAnsi(output).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let joined = kept.suffix(lines).joined(separator: " · ")
        return joined.count <= maxChars ? joined : String(joined.prefix(maxChars)) + "…"
    }

    private func firstNonEmpty(_ a: String?, _ b: String?) -> String? {
        if let first = a?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty { return first }
        if let second = b?.trimmingCharacters(in: .whitespacesAndNewlines), !second.isEmpty { return second }
        return nil
    }
}
