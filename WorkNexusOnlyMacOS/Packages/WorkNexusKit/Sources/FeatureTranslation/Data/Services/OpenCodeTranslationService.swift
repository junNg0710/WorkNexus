import CoreDomain
import Foundation

/// How long a single `opencode run` may take before we give up and kill it. The CLI has no timeout of its own: an
/// unauthenticated provider, a queued free-tier model or a stalled request can leave it running indefinitely.
public let openCodeTranslationTimeout: TimeInterval = 120

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

    private let processes: TimedCliProcesses

    public init(runner: CliRunner = CliRunner(), model: String? = nil, workingDir: String? = nil, binaryOverride: String? = nil,
                timeout: TimeInterval = openCodeTranslationTimeout) {
        self.runner = runner; self.model = model; self.workingDir = workingDir; self.binaryOverride = binaryOverride
        self.timeout = timeout
        processes = TimedCliProcesses(runner: runner)
    }

    public func contentHash(_ source: TicketSource) -> String { FeatureTranslation.contentHash(source.title, source.body) }

    public func cancel(_ ticketId: String) async { await processes.cancel(ticketId) }

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

    private func run(key: String, path: String, args: [String]) async -> CliRun? {
        await processes.run(key: key, path: path, args: args, directory: workingDir ?? NSHomeDirectory(), timeout: timeout)
    }

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

    func tail(_ output: String, lines: Int = 4, maxChars: Int = 400) -> String { cliTail(output, lines: lines, maxChars: maxChars) }
}
