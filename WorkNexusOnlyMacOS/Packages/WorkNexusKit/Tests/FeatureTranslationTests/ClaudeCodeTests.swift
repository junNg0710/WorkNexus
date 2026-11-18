/// Not in the Flutter app: Claude Code as a built-in AI provider.
import CoreDomain
import XCTest
@testable import FeatureTranslation

private final class Log: @unchecked Sendable {
    private let lock = NSLock(); private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

private struct Backend: TranslationService {
    let name: String; let log: Log
    func contentHash(_ source: TicketSource) -> String { name }
    func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String, model: String?) async -> Outcome<TranslationRecord> {
        log.add("\(name).translate \(model ?? "-")"); return .failure(.agent(name))
    }
    func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation> {
        log.add("\(name).text \(model ?? "-")"); return .success(TextTranslation(name))
    }
    func complete(key: String, prompt: String, model: String?) async -> Outcome<TextTranslation> {
        log.add("\(name).complete \(model ?? "-")"); return .success(TextTranslation(name))
    }
    func cancel(_ key: String) async { log.add("\(name).cancel \(key)") }
}

private struct NoApi: ConfiguredTranslationBackend {
    func contentHash(_ source: TicketSource) -> String { "api" }
    func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String, config: TranslationApiConfig) async -> Outcome<TranslationRecord> { .failure(.agent("api")) }
    func translateText(key: String, text: String, targetLang: String, config: TranslationApiConfig) async -> Outcome<TextTranslation> { .failure(.agent("api")) }
    func complete(key: String, prompt: String, config: TranslationApiConfig) async -> Outcome<TextTranslation> { .failure(.agent("api")) }
    func cancel(_ key: String) async {}
}

private struct Repo: AiSetupRepository {
    let setup: AiSetup
    func load() async -> Outcome<AiSetup> { .success(setup) }
    func save(_ setup: AiSetup) async -> Outcome<Void> { .success(()) }
}

private struct OpenCode: OpenCodeCli {
    func hasAuthenticatedProvider() async -> Bool { true }
    func listModels() async -> [String] { [] }
}

private struct Claude: ClaudeCodeCli {
    let value: ClaudeCodeStatus
    func status() async -> ClaudeCodeStatus { value }
}

final class ClaudeCodeTests: XCTestCase {
    private let claude = AiModelChoice(providerId: AiModelChoice.claudeCodeId, model: "sonnet")

    func testAClaudeCodeChoiceResolvesToClaudeCodeWithItsModel() {
        XCTAssertEqual(ResolveAiBackend()(AiSetup(translation: claude), purpose: .translation, callerModel: "legacy/m"), .claudeCode(model: "sonnet"))
        let noModel = AiSetup(translation: AiModelChoice(providerId: AiModelChoice.claudeCodeId))
        XCTAssertEqual(ResolveAiBackend()(noModel, purpose: .chat, callerModel: "legacy/m"), .claudeCode(model: nil),
                       "the OpenCode pin never leaks into Claude Code")
        XCTAssertEqual(AiSettingsLogic.displayName(.claudeCode(model: "sonnet")), "Claude Code (sonnet)")
        XCTAssertEqual(AiSettingsLogic.choiceIds(.empty), [AiModelChoice.openCodeId, AiModelChoice.claudeCodeId])
    }

    func testRoutingSendsEachPurposeToItsBackend() async {
        let log = Log()
        let setup = AiSetup(translation: .openCodeDefault, chat: claude)
        let r = RoutingTranslationService(api: NoApi(), openCode: Backend(name: "oc", log: log), claudeCode: Backend(name: "cc", log: log),
                                          setup: { setup })
        _ = await r.translateText(key: "t", text: "x", targetLang: "vi", model: nil)
        _ = await r.complete(key: "c", prompt: "p", model: nil)
        XCTAssertEqual(log.all, ["oc.text -", "cc.complete sonnet"])
    }

    func testReadinessFollowsTheClaudeLogin() async {
        let setup = AiSetup(translation: claude)
        let ready = await CheckTranslationReady(setup: Repo(setup: setup), cli: OpenCode(), claude: Claude(value: .loggedIn)).readiness()
        let out = await CheckTranslationReady(setup: Repo(setup: setup), cli: OpenCode(), claude: Claude(value: .loggedOut)).readiness()
        let missing = await CheckTranslationReady(setup: Repo(setup: setup), cli: OpenCode()).readiness()
        XCTAssertEqual([ready, out, missing], [.ready, .claudeCodeLoggedOut, .claudeCodeNotInstalled])
    }

    func testTheRunIsAPlainQuestionWithEveryToolOff() {
        let args = ClaudeCodeTranslationService.arguments(prompt: "Translate this", model: " haiku ")
        XCTAssertEqual(Array(args.prefix(2)), ["-p", "Translate this"], "the prompt comes before --tools, which takes a list")
        XCTAssertEqual(args[args.firstIndex(of: "--tools")! + 1], "")
        for flag in ["--no-session-persistence", "--strict-mcp-config", "--disable-slash-commands"] { XCTAssertTrue(args.contains(flag), flag) }
        XCTAssertEqual(args.suffix(2), ["--model", "haiku"])
        XCTAssertFalse(ClaudeCodeTranslationService.arguments(prompt: "p", model: "").contains("--model"))
    }

    func testTheAnswerIsTheJsonResultWithItsModel() {
        let ok = CliRun(exitCode: 0, stdout: #"{"type":"result","subtype":"success","is_error":false,"result":" Chào cả nhóm ","modelUsage":{"claude-haiku-5-5":{}}}"#,
                        stderr: "", timedOut: false)
        XCTAssertEqual(ClaudeCodeTranslationService.answer(ok).value, ClaudeCodeAnswer(text: "Chào cả nhóm", model: "claude-haiku-5-5"))
        let refused = CliRun(exitCode: 1, stdout: #"{"is_error":true,"result":"Not logged in · Please run /login"}"#, stderr: "", timedOut: false)
        guard case .failure(.agent(let m)) = ClaudeCodeTranslationService.answer(refused) else { return XCTFail() }
        XCTAssertTrue(m.contains("Not logged in"))
        let garbage = CliRun(exitCode: 127, stdout: "", stderr: "claude: command failed", timedOut: false)
        guard case .failure(.agent(let g)) = ClaudeCodeTranslationService.answer(garbage) else { return XCTFail() }
        XCTAssertTrue(g.contains("command failed"))
    }

    func testOnlyTheLoginFlagIsReadFromTheAuthStatus() {
        XCTAssertEqual(ClaudeCodeCliRunner.status(fromAuthJson: #"{"loggedIn":true,"authMethod":"claude.ai"}"#), .loggedIn)
        XCTAssertEqual(ClaudeCodeCliRunner.status(fromAuthJson: #"{"loggedIn":false}"#), .loggedOut)
        XCTAssertEqual(ClaudeCodeCliRunner.status(fromAuthJson: "Not logged in"), .loggedOut)
    }

    func testTheModelDropdownOffersTheAliasesAndKeepsATypedModel() {
        XCTAssertEqual(ClaudeCodeModels.choices(selected: ""), ["", "haiku", "sonnet", "opus"])
        XCTAssertEqual(ClaudeCodeModels.choices(selected: "claude-opus-5-5"), ["", "haiku", "sonnet", "opus", "claude-opus-5-5"])
    }
}

final class CliLookupTests: XCTestCase {
    /// A login shell that leaves a background job holding its output open (a version manager, a prompt helper) used to hang
    /// the lookup forever; it now returns once the shell exits.
    func testALookupReturnsWhenTheShellExitsEvenIfABackgroundJobKeepsTheOutputOpen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cli-lookup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shell = dir.appendingPathComponent("fake-shell")
        try "#!/bin/sh\necho /opt/fake/bin/claude\n(sleep 30) &\n".write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        let runner = CliRunner(environment: ["SHELL": shell.path, "PATH": ""], fileExists: { _ in true })
        let started = Date()
        let path = await runner.resolve("claude")
        XCTAssertEqual(path, "/opt/fake/bin/claude")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
}
