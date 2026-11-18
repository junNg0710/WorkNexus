import CoreDomain
import Foundation

/// How long one `claude -p` run may take before it is stopped.
public let claudeCodeTimeout: TimeInterval = 120

/// Not in the Flutter app.
/// Translation and chat AI through the Claude Code CLI (`claude -p`), on the user's own Claude login (a Pro / Max / Team
/// plan or a Console account): no API key, and the app never reads the login itself. Each run is a single answer: every
/// tool, MCP server, setting file, slash command and session file is switched off, and it runs in an empty folder, so
/// Claude Code only reads the prompt and writes text.
public final class ClaudeCodeTranslationService: TranslationService, @unchecked Sendable {
    private let runner: CliRunner
    private let processes: TimedCliProcesses
    private let binaryOverride: String?
    private let timeout: TimeInterval
    private static let templateVersion = "cc-v1"
    static let systemPrompt = "You are a translation and writing assistant inside a work app. Answer with the requested text only: no preamble, no tools, no questions."

    public init(runner: CliRunner = CliRunner(), binaryOverride: String? = nil, timeout: TimeInterval = claudeCodeTimeout) {
        self.runner = runner; self.binaryOverride = binaryOverride; self.timeout = timeout
        processes = TimedCliProcesses(runner: runner)
    }

    public func contentHash(_ source: TicketSource) -> String { FeatureTranslation.contentHash(source.title, source.body) }

    public func cancel(_ ticketId: String) async { await processes.cancel(ticketId) }

    public func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String,
                          model: String?) async -> Outcome<TranslationRecord> {
        let language = translationLanguage(for: targetLang)
        switch await ask(key: ticketId, prompt: ticketPrompt(source, language.englishName), model: model) {
        case .failure(let f): return .failure(f)
        case .success(let answer):
            guard let parsed = extractTicketJson(answer.text) else { return .failure(.parse("Could not parse the translation: \(cliTail(answer.text))")) }
            return .success(ticketRecord(parsed: parsed, ticketId: ticketId, source: source, sourceHash: sourceHash, lang: language.code,
                                         model: answer.model ?? "claude-code", templateVersion: Self.templateVersion))
        }
    }

    public func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation> {
        let language = translationLanguage(for: targetLang)
        return await complete(key: key, prompt: textPrompt(text, language.englishName), model: model)
    }

    public func complete(key: String, prompt: String, model: String?) async -> Outcome<TextTranslation> {
        switch await ask(key: key, prompt: prompt, model: model) {
        case .failure(let f): return .failure(f)
        case .success(let answer): return .success(TextTranslation(answer.text, model: answer.model))
        }
    }

    private func ask(key: String, prompt: String, model: String?) async -> Outcome<ClaudeCodeAnswer> {
        guard let path = await runner.resolve("claude", override: binaryOverride) else { return .failure(.agent("Claude Code (claude) not found on PATH")) }
        guard let run = await processes.run(key: key, path: path, args: Self.arguments(prompt: prompt, model: model),
                                            directory: Self.emptyDirectory(), timeout: timeout) else {
            return .failure(.agent("Claude Code could not start"))
        }
        if run.timedOut { return .failure(.agent("Claude Code did not answer within \(Int(timeout))s and was stopped.")) }
        return Self.answer(run)
    }

    /// `claude -p` as a plain question: the prompt first (`--tools` takes a list and would swallow a prompt after it).
    static func arguments(prompt: String, model: String?) -> [String] {
        var args = ["-p", prompt, "--output-format", "json", "--tools", "", "--no-session-persistence", "--strict-mcp-config",
                    "--setting-sources", "", "--disable-slash-commands", "--system-prompt", systemPrompt]
        if let m = model?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { args += ["--model", m] }
        return args
    }

    /// What one run answered: the `result` of its JSON, and the model that wrote it (the first of `modelUsage`).
    static func answer(_ run: CliRun) -> Outcome<ClaudeCodeAnswer> {
        let raw = run.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let json = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else {
            let detail = firstNonEmpty(run.stderr, run.stdout).map { cliTail($0) } ?? "exit \(run.exitCode)"
            return .failure(.agent("Claude Code failed: \(detail)"))
        }
        let text = (json["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if json["is_error"] as? Bool == true || run.exitCode != 0 {
            return .failure(.agent("Claude Code failed: \(text.isEmpty ? (json["subtype"] as? String ?? "error") : cliTail(text))"))
        }
        guard !text.isEmpty else { return .failure(.parse("Claude Code returned nothing")) }
        let model = (json["modelUsage"] as? [String: Any])?.keys.sorted().first
        return .success(ClaudeCodeAnswer(text: text, model: model))
    }

    /// An empty folder of the app's own to run in: no project files or CLAUDE.md for Claude Code to pick up.
    static func emptyDirectory() -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("worknexus-claude-code", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}

struct ClaudeCodeAnswer: Equatable { var text: String; var model: String? }
