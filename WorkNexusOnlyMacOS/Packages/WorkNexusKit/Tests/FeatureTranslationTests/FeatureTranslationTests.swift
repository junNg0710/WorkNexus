import CoreDomain
import CorePersistence
import XCTest
@testable import FeatureTranslation

// MARK: doubles

private final class StubHTTP: TranslationHTTPClient, @unchecked Sendable {
    let status: Int; let body: Any
    private(set) var last: URLRequest?
    init(_ status: Int, _ body: Any) { self.status = status; self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        last = request
        let data = try JSONSerialization.data(withJSONObject: body)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private func reply(_ content: String) -> [String: Any] { ["choices": [["message": ["content": content]]]] }

private let config = TranslationApiConfig(presetId: "groq", baseUrl: "https://api.example.test/v1/", model: "m-1", apiKey: "sk-test")

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("translation_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private struct Marker: TranslationService {
    let name: String
    func contentHash(_ source: TicketSource) -> String { name }
    func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String, model: String?) async -> Outcome<TranslationRecord> { .failure(.agent(name)) }
    func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation> { .success(TextTranslation(name)) }
    func complete(key: String, prompt: String, model: String?) async -> Outcome<TextTranslation> { .success(TextTranslation(name)) }
    func cancel(_ ticketId: String) async {}
}

// MARK: api_translation_service_test.dart

final class ApiTranslationServiceTests: XCTestCase {
    private func service(_ http: StubHTTP, _ c: TranslationApiConfig? = nil) -> ApiTranslationService {
        let cfg = c ?? config
        return ApiTranslationService(http: http, config: { cfg })
    }

    func testTranslateTextPostsWithKeyAndReturnsText() async throws {
        let http = StubHTTP(200, reply("  Xin chào  "))
        let r = await service(http).translateText(key: "k", text: "Hello", targetLang: "vi", model: nil)
        XCTAssertEqual(r.value?.text, "Xin chào")
        XCTAssertEqual(r.value?.model, "m-1")
        XCTAssertEqual(http.last?.url?.absoluteString, "https://api.example.test/v1/chat/completions")
        XCTAssertEqual(http.last?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let sent = try JSONSerialization.jsonObject(with: XCTUnwrap(http.last?.httpBody)) as? [String: Any]
        XCTAssertEqual(sent?["model"] as? String, "m-1")
    }

    func testCompleteSendsThePromptAsIsAndReturnsTheReply() async throws {
        let http = StubHTTP(200, reply(" Three points. "))
        let r = await service(http).complete(key: "k", prompt: "Summarize this", model: nil)
        XCTAssertEqual(r.value?.text, "Three points.")
        let sent = try JSONSerialization.jsonObject(with: XCTUnwrap(http.last?.httpBody)) as? [String: Any]
        let messages = sent?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["content"] as? String, "Summarize this")
    }

    func testRoutingSendsAPromptToThePickedBackend() async {
        let routing = RoutingTranslationService(api: Marker(name: "api"), openCode: Marker(name: "opencode"), config: { nil })
        let r = await routing.complete(key: "k", prompt: "p", model: nil)
        XCTAssertEqual(r.value?.text, "opencode")
    }

    func testTicketReplyWrappedInCodeFenceIsParsed() async {
        let http = StubHTTP(200, reply("```json\n{\"title\":\"Tiêu đề\",\"body\":\"Nội dung\"}\n```"))
        let r = await service(http).translate(ticketId: "t", source: TicketSource(title: "Title", body: "Body"), sourceHash: "h", targetLang: "vi", model: nil)
        XCTAssertEqual(r.value?.translatedTitle, "Tiêu đề")
        XCTAssertEqual(r.value?.model, "m-1")
        XCTAssertEqual(r.value?.sourceHash, "h")
    }

    func test401IsRejectedKeyAnd429IsRateLimit() async {
        let bad = await service(StubHTTP(401, ["error": ["message": "bad key"]])).translateText(key: "k", text: "x", targetLang: "vi", model: nil)
        let busy = await service(StubHTTP(429, ["error": ["message": "slow down"]])).translateText(key: "k", text: "x", targetLang: "vi", model: nil)
        guard case .failure(.auth(let m)) = bad else { return XCTFail("expected auth failure") }
        XCTAssertTrue(m.contains("bad key"))
        XCTAssertTrue(busy.failure?.message.contains("rate limit") == true)
    }

    func testNoUsableConfigIsAuthFailureNotARequest() async {
        let http = StubHTTP(200, reply("x"))
        var off = config; off.enabled = false
        let r = await service(http, off).translateText(key: "k", text: "x", targetLang: "vi", model: nil)
        guard case .failure(.auth) = r else { return XCTFail("expected auth failure") }
        XCTAssertNil(http.last)
    }

    func testEmptyReplyIsParseFailure() async {
        let r = await service(StubHTTP(200, reply("   "))).translateText(key: "k", text: "x", targetLang: "vi", model: nil)
        guard case .failure(.parse) = r else { return XCTFail("expected parse failure") }
    }

    func testRoutingPicksBackendByConfig() async {
        func run(_ c: TranslationApiConfig?) async -> String? {
            let routing = RoutingTranslationService(api: Marker(name: "api"), openCode: Marker(name: "opencode"), config: { c })
            return await routing.translateText(key: "k", text: "x", targetLang: "vi", model: nil).value?.text
        }
        let apiPick = await run(config), nilPick = await run(nil)
        var off = config; off.enabled = false
        let offPick = await run(off)
        XCTAssertEqual(apiPick, "api")
        XCTAssertEqual(nilPick, "opencode")
        XCTAssertEqual(offPick, "opencode")
    }
}

// MARK: openai_model_catalog_datasource_test.dart

final class ModelCatalogTests: XCTestCase {
    func testListsChatModelsStrippingGeminiPrefix() async {
        let http = StubHTTP(200, ["data": [["id": "models/gemini-3.8-flash"], ["id": "models/text-embedding-004"], ["id": "models/gemini-3.8-pro"]]])
        let r = await OpenAIModelCatalogDataSource(http: http).listModels(baseUrl: "https://example.test/v1/", apiKey: "k")
        XCTAssertEqual(r.value, ["gemini-3.8-flash", "gemini-3.8-pro"])
        XCTAssertEqual(http.last?.url?.absoluteString, "https://example.test/v1/models")
        XCTAssertEqual(http.last?.value(forHTTPHeaderField: "Authorization"), "Bearer k")
    }

    func testRejectedKeyIsAuthFailure() async {
        let r = await OpenAIModelCatalogDataSource(http: StubHTTP(401, ["error": "bad key"])).listModels(baseUrl: "https://x.test", apiKey: "")
        guard case .failure(.auth) = r else { return XCTFail("expected auth failure") }
    }

    func testUnexpectedBodyIsParseFailure() async {
        let r = await OpenAIModelCatalogDataSource(http: StubHTTP(200, ["models": []])).listModels(baseUrl: "https://x.test", apiKey: "")
        guard case .failure(.parse) = r else { return XCTFail("expected parse failure") }
    }
}

// MARK: opencode_translation_timeout_test.dart (a scripted fake `opencode` binary)

final class OpenCodeTranslationTests: XCTestCase {
    private let source = TicketSource(title: "Fix login", body: "It does not respond.")
    private var dir: URL!
    override func setUp() { dir = tempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func fakeBinary(_ script: String) throws -> String {
        let url = dir.appendingPathComponent("opencode-\(UUID().uuidString)")
        try "#!/bin/sh\n\(script)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func service(_ script: String, timeout: TimeInterval = 30) throws -> OpenCodeTranslationService {
        OpenCodeTranslationService(binaryOverride: try fakeBinary(script), timeout: timeout)
    }

    private func translate(_ s: OpenCodeTranslationService) async -> Outcome<TranslationRecord> {
        await s.translate(ticketId: "t-1", source: source, sourceHash: "hash-1", targetLang: "vi", model: nil)
    }

    func testCliThatNeverAnswersIsKilledAndReported() async throws {
        let start = Date()
        let r = await translate(try service("sleep 30", timeout: 0.3))
        guard case .failure(.agent(let m)) = r else { return XCTFail("expected agent failure, got \(r)") }
        XCTAssertTrue(m.contains("did not answer"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "the child must be killed, not abandoned")
    }

    func testProviderErrorReachesUserWithCliWords() async throws {
        let r = await translate(try service("echo \"Token refresh failed: 401\" >&2; exit 1"))
        let m = r.failure?.message ?? ""
        XCTAssertTrue(m.contains("exited 1")); XCTAssertTrue(m.contains("Token refresh failed: 401"))
    }

    func testTerminalColourCodesAreStripped() async throws {
        let r = await translate(try service(#"printf '\033[91m\033[1mError: \033[0mmodel requires opt in\n' >&2; exit 1"#))
        let m = r.failure?.message ?? ""
        XCTAssertTrue(m.contains("Error: model requires opt in"))
        XCTAssertFalse(m.contains("\u{1B}"))
    }

    func testSuccessfulRunIsParsedIntoRecord() async throws {
        let r = await translate(try service(#"echo '{"title":"Sửa đăng nhập","body":"Không phản hồi."}'"#))
        let rec = try XCTUnwrap(r.value)
        XCTAssertEqual(rec.translatedTitle, "Sửa đăng nhập")
        XCTAssertEqual(rec.translatedBody, "Không phản hồi.")
        XCTAssertEqual(rec.targetLang, "vi"); XCTAssertEqual(rec.sourceHash, "hash-1")
        XCTAssertEqual(rec.model, "opencode default")
    }

    func testModelIsPassedAndRecorded() async throws {
        let argsFile = dir.appendingPathComponent("args.txt").path
        let s = try service("echo \"$@\" > '\(argsFile)'; echo '{\"title\":\"a\",\"body\":\"b\"}'")
        let r = await s.translate(ticketId: "t", source: source, sourceHash: "h", targetLang: "vi", model: " opencode-go/x ")
        XCTAssertEqual(r.value?.model, "opencode-go/x")
        let args = try String(contentsOfFile: argsFile, encoding: .utf8)
        XCTAssertTrue(args.hasPrefix("run -m opencode-go/x Translate this software ticket into natural, technical Vietnamese"))
    }

    func testOutputWithoutJsonIsParseFailureQuotingOutput() async throws {
        let r = await translate(try service("echo \"usage: opencode run [message..]\""))
        guard case .failure(.parse(let m)) = r else { return XCTFail("expected parse failure") }
        XCTAssertTrue(m.contains("usage: opencode run"))
    }

    func testCancelStopsInFlightRun() async throws {
        let s = try service("sleep 30")
        let pending = Task { await translate(s) }
        try await Task.sleep(for: .milliseconds(400))
        await s.cancel("t-1")
        let r = await pending.value
        XCTAssertNotNil(r.failure)
    }

    func testTranslateTextStripsAnsiAndTrims() async throws {
        let s = try service(#"printf '\033[0m  Xin chào\n'"#)
        let r = await s.translateText(key: "k", text: "Hello", targetLang: "vi", model: nil)
        XCTAssertEqual(r.value?.text, "Xin chào")
    }

    func testMissingBinaryIsAgentFailure() async {
        let runner = CliRunner(environment: ["PATH": "/nonexistent", "SHELL": "/bin/sh"], runProcess: { _, _ in nil }, fileExists: { _ in false })
        let r = await translate(OpenCodeTranslationService(runner: runner))
        guard case .failure(.agent(let m)) = r else { return XCTFail("expected agent failure") }
        XCTAssertTrue(m.contains("not found"))
    }
}

// MARK: cli_runner_resolve_test.dart

final class CliRunnerResolveTests: XCTestCase {
    func testAsksLoginShellFirstTakingLastAbsoluteLine() async {
        let seen = Locked<[[String]]>([])
        let runner = CliRunner(environment: ["SHELL": "/bin/zsh"], runProcess: { exe, args in
            seen.withLock { $0.append([exe] + args) }
            return "Last login: today\nsome banner\n/Users/dev/.local/bin/opencode\n"
        }, fileExists: { _ in true })
        let p = await runner.resolve("opencode")
        XCTAssertEqual(p, "/Users/dev/.local/bin/opencode")
        XCTAssertEqual(seen.withLock { $0 }.first, ["/bin/zsh", "-lic", "command -v opencode"])
    }

    func testFallsBackToPathScanAndCachesHits() async {
        let calls = Locked(0)
        let runner = CliRunner(environment: ["PATH": "/a:/b", "SHELL": "/bin/sh"], runProcess: { _, _ in calls.withLock { $0 += 1 }; return nil },
                               fileExists: { $0 == "/b/opencode" })
        let first = await runner.resolve("opencode")
        let second = await runner.resolve("opencode")
        XCTAssertEqual(first, "/b/opencode"); XCTAssertEqual(second, "/b/opencode")
        XCTAssertEqual(calls.withLock { $0 }, 1, "a hit is remembered: the login shell is spawned once")
    }

    func testOverrideWins() async {
        let p = await CliRunner(runProcess: { _, _ in XCTFail("not asked"); return nil }).resolve("opencode", override: "  /x/opencode ")
        XCTAssertEqual(p, "/x/opencode")
    }
}

final class CliRunnerKillTreeTests: XCTestCase {
    func testKillTreeStopsDescendants() async throws {
        // sh starts a background sleep; killing only the shell would leave the sleep behind.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 30 & echo $! ; wait"]
        let out = Pipe(); p.standardOutput = out
        try p.run()
        try await Task.sleep(for: .milliseconds(300))
        let line = String(decoding: out.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let child = try XCTUnwrap(Int32(line))
        await CliRunner().killTree(p)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotEqual(kill(child, 0), 0, "the grandchild must be gone")
        XCTAssertFalse(p.isRunning)
    }
}

// MARK: opencode_auth_file_key_repository_test.dart

final class OpenCodeKeyRepositoryTests: XCTestCase {
    private var dir: URL!
    private var authFile: URL!
    private var repo: OpenCodeAuthFileKeyRepository!
    override func setUp() {
        dir = tempDir(); authFile = dir.appendingPathComponent("auth.json")
        repo = OpenCodeAuthFileKeyRepository(file: OpenCodeAuthFile(path: authFile.path))
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    private func writeAuth(_ e: [String: Any]) throws { try JSONSerialization.data(withJSONObject: e).write(to: authFile) }

    func testApiKeyReadsMaskedOAuthHasNoPreview() async throws {
        try writeAuth(["opencode": ["type": "api", "key": "sk-000011112222n5UT"], "anthropic": ["type": "oauth", "access": "a", "refresh": "r"]])
        let api = await repo.authFor(providerId: "opencode").value
        let oauth = await repo.authFor(providerId: "anthropic").value
        let none = await repo.authFor(providerId: "groq").value
        XCTAssertEqual(api, OpenCodeProviderAuth(linked: true, keyPreview: "••••••n5UT"))
        XCTAssertEqual(oauth, OpenCodeProviderAuth(linked: true, keyPreview: nil))
        XCTAssertEqual(none, OpenCodeProviderAuth.none)
    }

    func testSavingReplacesOneProviderKeepsOthersAndLocksPermissions() async throws {
        try writeAuth(["opencode": ["type": "api", "key": "old"], "anthropic": ["type": "oauth", "access": "a"]])
        let r = await repo.saveApiKey(providerId: "opencode", key: " new-key ")
        XCTAssertNotNil(r.value)
        let stored = try JSONSerialization.jsonObject(with: Data(contentsOf: authFile)) as? [String: [String: String]]
        XCTAssertEqual(stored?["opencode"], ["type": "api", "key": "new-key"])
        XCTAssertEqual(stored?["anthropic"], ["type": "oauth", "access": "a"])
        let perms = try FileManager.default.attributesOfItem(atPath: authFile.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: authFile.path + ".worknexus.tmp"))
    }

    func testRemovingDropsOnlyThatProvidersApiKey() async throws {
        try writeAuth(["opencode": ["type": "api", "key": "k"], "groq": ["type": "api", "key": "g"], "anthropic": ["type": "oauth", "access": "a"]])
        let removed = await repo.removeApiKey(providerId: "opencode").value
        let oauth = await repo.removeApiKey(providerId: "anthropic").value   // an OAuth login stays
        let missing = await repo.removeApiKey(providerId: "missing").value   // nothing to remove: success
        XCTAssertNotNil(removed); XCTAssertNotNil(oauth); XCTAssertNotNil(missing)
        let stored = try JSONSerialization.jsonObject(with: Data(contentsOf: authFile)) as? [String: [String: String]]
        XCTAssertNil(stored?["opencode"])
        XCTAssertEqual(stored?["groq"], ["type": "api", "key": "g"])
        XCTAssertEqual(stored?["anthropic"], ["type": "oauth", "access": "a"])
        let after = await repo.authFor(providerId: "opencode").value
        XCTAssertEqual(after, OpenCodeProviderAuth.none)
    }

    func testRemovingFromAMalformedFileLeavesItAlone() async throws {
        try "{not json".write(to: authFile, atomically: true, encoding: .utf8)
        let r = await repo.removeApiKey(providerId: "x")
        guard case .failure(.parse) = r else { return XCTFail("expected parse failure") }
        XCTAssertEqual(try String(contentsOf: authFile, encoding: .utf8), "{not json")
    }

    func testFirstSaveCreatesTheFile() async {
        let nested = OpenCodeAuthFileKeyRepository(file: OpenCodeAuthFile(path: dir.appendingPathComponent("a/b/auth.json").path))
        _ = await nested.saveApiKey(providerId: "opencode", key: "k")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a/b/auth.json").path))
    }

    func testMalformedFileIsLeftAlone() async throws {
        try "{not json".write(to: authFile, atomically: true, encoding: .utf8)
        let r = await repo.saveApiKey(providerId: "x", key: "k")
        guard case .failure(.parse) = r else { return XCTFail("expected parse failure") }
        XCTAssertEqual(try String(contentsOf: authFile, encoding: .utf8), "{not json")
    }

    func testResolvePrefersXdgThenDotLocalShare() throws {
        let xdg = dir.appendingPathComponent("xdg").path
        let file = OpenCodeAuthFile(environment: ["HOME": dir.path, "XDG_DATA_HOME": xdg])
        XCTAssertEqual(file.resolve().path, "\(xdg)/opencode/auth.json")   // none exist: preferred location
        try FileManager.default.createDirectory(atPath: "\(dir.path)/.local/share/opencode", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: "\(dir.path)/.local/share/opencode/auth.json", contents: Data("{}".utf8))
        XCTAssertEqual(file.resolve().path, "\(dir.path)/.local/share/opencode/auth.json")
    }

    func testKeyBelongsToProviderOfChosenModel() {
        XCTAssertEqual(openCodeProvider(of: "opencode/longcat-2.5-preview-free"), "opencode")
        XCTAssertEqual(openCodeProvider(of: "anthropic/claude-x"), "anthropic")
        XCTAssertEqual(openCodeProvider(of: ""), "opencode")
        XCTAssertEqual(openCodeKeyUrl("Google"), "https://aistudio.google.com/apikey")
    }
}

// MARK: credential_translation_api_config_repository_test.dart

private actor CountingStore: CredentialStore {
    private var values: [String: String] = [:]
    private(set) var reads = 0
    func read(_ key: String) async -> String? { reads += 1; return values[key] }
    func write(_ key: String, value: String) async -> Outcome<Void> { values[key] = value; return .success(()) }
    func delete(_ key: String) async -> Outcome<Void> { values[key] = nil; return .success(()) }
}

final class ApiConfigRepositoryTests: XCTestCase {
    private let cfg = TranslationApiConfig(presetId: "groq", baseUrl: "https://api.example.test/v1", model: "m", apiKey: "k")

    func testStoredConfigIsReadOnceNotOnEveryTranslation() async {
        let store = CountingStore(); let repo = CredentialTranslationApiConfigRepository(store: store)
        _ = await repo.save(cfg)
        _ = await repo.load(); _ = await repo.load()
        let loaded = await repo.load().value ?? nil
        XCTAssertEqual(loaded?.model, "m")
        let reads = await store.reads
        XCTAssertEqual(reads, 0, "save primes the cache")
    }

    func testClearAndSaveAreSeenByNextLoad() async {
        let store = CountingStore(); let repo = CredentialTranslationApiConfigRepository(store: store)
        let first = await repo.load().value ?? nil
        XCTAssertNil(first)
        var reads = await store.reads
        XCTAssertEqual(reads, 1)
        _ = await repo.save(cfg)
        let saved = await repo.load().value ?? nil
        XCTAssertEqual(saved?.apiKey, "k")
        _ = await repo.clear()
        let cleared = await repo.load().value ?? nil
        XCTAssertNil(cleared)
        reads = await store.reads
        XCTAssertEqual(reads, 1)
    }

    func testStoredJsonShapeMatchesFlutterBuild() async throws {
        let store = CountingStore(); let repo = CredentialTranslationApiConfigRepository(store: store)
        _ = await repo.save(cfg)
        let stored = await store.read(CredentialKey.translationApi)
        let raw = try XCTUnwrap(stored)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["preset", "baseUrl", "model", "apiKey", "enabled"])
        // A fresh repository (new session) decodes what the Flutter build wrote.
        let reloaded = await CredentialTranslationApiConfigRepository(store: store).load().value ?? nil
        XCTAssertEqual(reloaded, cfg)
    }
}

// MARK: translation_state_test.dart, translation_languages_test.dart, content hash, cache repository

final class TranslationDomainTests: XCTestCase {
    private func rec(_ hash: String) -> TranslationRecord {
        TranslationRecord(ticketId: "t", sourceHash: hash, targetLang: "vi", translatedTitle: "Tiêu đề", translatedBody: "Nội dung",
                          model: "m", templateVersion: "v1", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testStateResolution() {
        let resolve = ResolveTranslationState()
        XCTAssertEqual(resolve(currentSourceHash: "h1", record: nil), .none)
        XCTAssertEqual(resolve(currentSourceHash: "h1", record: nil, hasError: true), .error)
        XCTAssertEqual(resolve(currentSourceHash: "h1", record: rec("h1")), .done)
        XCTAssertEqual(resolve(currentSourceHash: "h2", record: rec("h1")), .outdated)
        XCTAssertEqual(resolve(currentSourceHash: "h1", record: rec("h1"), loading: true), .loading)
        XCTAssertEqual(resolve(currentSourceHash: "h1", record: nil, loading: true, hasError: true), .loading)
    }

    func testLanguageLookupFallsBackToDefault() {
        XCTAssertEqual(translationLanguage(for: "ja").englishName, "Japanese")
        XCTAssertEqual(translationLanguage(for: "xx").code, defaultTranslationLang)
        XCTAssertEqual(translationLanguages.first?.code, "vi")
    }

    func testContentHashMatchesDartAlgorithm() {
        // Dart: h = (h*31 + codeUnit) & 0x7fffffff over "$title $body"; "a b" → ((97*31+32)*31+98) = 94,  computed by hand.
        XCTAssertEqual(intHash("a b"), ((97 * 31 + 32) * 31 + 98) & 0x7fff_ffff)
        XCTAssertEqual(contentHash("a", "b"), String(((97 * 31 + 32) * 31 + 98), radix: 16))
        XCTAssertEqual(contentHash("Fix", "Mã"), contentHash("Fix", "Mã"))
        XCTAssertNotEqual(contentHash("a", "b"), contentHash("a", "c"))
        // Non-BMP characters hash as two UTF-16 units, like Dart's codeUnitAt.
        XCTAssertEqual(intHash("😀"), (Int(0xD83D) * 31 + Int(0xDE00)) & 0x7fff_ffff)
    }

    func testPresetLookup() {
        XCTAssertEqual(TranslationApiPreset.byId("groq").name, "Groq")
        XCTAssertEqual(TranslationApiPreset.byId("nope"), .custom)
        XCTAssertFalse(TranslationApiPreset.byId("ollama").needsKey)
        XCTAssertTrue(TranslationApiPreset.openCode.isOpenCode)
    }

    func testOpenCodeCliOutputParsing() {
        XCTAssertEqual(OpenCodeCliRunner.credentialCount("┌ Credentials\n│\n└  2 credentials"), 2)
        XCTAssertEqual(OpenCodeCliRunner.credentialCount("0 credentials"), 0)
        XCTAssertNil(OpenCodeCliRunner.credentialCount("nothing"))
        XCTAssertEqual(OpenCodeCliRunner.modelIds("banner\nopencode/b\nanthropic/claude-x:1\nopencode/b\nError: x/\n"), ["anthropic/claude-x:1", "opencode/b"])
    }

    func testGRDBCacheRoundTripAndObservation() async throws {
        let db = try AppDatabase.inMemory()
        let repo = GRDBTranslationRepository(database: db)
        let missing = await repo.translation(ticketId: "t").value ?? nil
        XCTAssertNil(missing)
        let record = rec("h1")
        _ = await repo.saveTranslation(record)
        let got = await repo.translation(ticketId: "t").value ?? nil
        XCTAssertEqual(got?.translatedTitle, "Tiêu đề")
        XCTAssertEqual(got?.createdAt.timeIntervalSince1970 ?? 0, record.createdAt.timeIntervalSince1970, accuracy: 0.01)
        // saving again replaces (insert-or-update on the ticket id)
        var newer = record; newer.sourceHash = "h2"; newer.translatedBody = "Mới"
        _ = await repo.saveTranslation(newer)
        let replaced = await repo.translation(ticketId: "t").value ?? nil
        XCTAssertEqual(replaced?.sourceHash, "h2")
        var iterator = repo.watchTranslation(ticketId: "t").makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first??.translatedBody, "Mới")
    }
}
