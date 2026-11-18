/// Not in the Flutter app: several AI providers and a provider + model per purpose.
import CoreDomain
import XCTest
@testable import FeatureTranslation

// MARK: doubles (no keychain, no network)

private actor FakeStore: CredentialStore {
    var values: [String: String] = [:]
    private(set) var reads = 0
    init(_ values: [String: String] = [:]) { self.values = values }
    func read(_ key: String) async -> String? { reads += 1; return values[key] }
    func write(_ key: String, value: String) async -> Outcome<Void> { values[key] = value; return .success(()) }
    func delete(_ key: String) async -> Outcome<Void> { values[key] = nil; return .success(()) }
}

private final class RecordingHTTP: TranslationHTTPClient, @unchecked Sendable {
    let body: Any
    private(set) var last: URLRequest?
    init(_ body: Any) { self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        last = request
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// Records what each backend was asked, with which config / model.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

private struct FakeApi: ConfiguredTranslationBackend {
    let calls: Calls
    func contentHash(_ source: TicketSource) -> String { "api" }
    func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String, config: TranslationApiConfig) async -> Outcome<TranslationRecord> {
        calls.add("api.translate \(config.presetId) \(config.model) \(config.apiKey)"); return .failure(.agent("api"))
    }
    func translateText(key: String, text: String, targetLang: String, config: TranslationApiConfig) async -> Outcome<TextTranslation> {
        calls.add("api.text \(config.presetId) \(config.model) \(config.apiKey)"); return .success(TextTranslation("api"))
    }
    func complete(key: String, prompt: String, config: TranslationApiConfig) async -> Outcome<TextTranslation> {
        calls.add("api.complete \(config.presetId) \(config.model) \(config.apiKey)"); return .success(TextTranslation("api"))
    }
    func cancel(_ key: String) async { calls.add("api.cancel \(key)") }
}

private struct FakeOpenCode: TranslationService {
    let calls: Calls
    func contentHash(_ source: TicketSource) -> String { "oc" }
    func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String, model: String?) async -> Outcome<TranslationRecord> {
        calls.add("oc.translate \(model ?? "-")"); return .failure(.agent("oc"))
    }
    func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation> {
        calls.add("oc.text \(model ?? "-")"); return .success(TextTranslation("oc"))
    }
    func complete(key: String, prompt: String, model: String?) async -> Outcome<TextTranslation> {
        calls.add("oc.complete \(model ?? "-")"); return .success(TextTranslation("oc"))
    }
    func cancel(_ key: String) async { calls.add("oc.cancel \(key)") }
}

private let openai = AiProvider(id: "openai", presetId: "openai", name: "OpenAI", baseUrl: "https://api.openai.com/v1", apiKey: "sk-o")
private let claude = AiProvider(id: "anthropic", presetId: "anthropic", name: "Anthropic Claude", baseUrl: "https://api.anthropic.com/v1", apiKey: "sk-a")

// MARK: resolution

final class ResolveAiBackendTests: XCTestCase {
    private let resolve = ResolveAiBackend()

    func testChatFollowsTranslationUntilItHasItsOwnChoice() {
        var setup = AiSetup(providers: [openai, claude], translation: AiModelChoice(providerId: "openai", model: "gpt-5"))
        guard case .api(let p, let c) = resolve(setup, purpose: .chat) else { return XCTFail("expected the API") }
        XCTAssertEqual(p.id, "openai"); XCTAssertEqual(c.model, "gpt-5"); XCTAssertEqual(c.apiKey, "sk-o")
        setup.chat = AiModelChoice(providerId: "anthropic")
        guard case .api(let p2, let c2) = resolve(setup, purpose: .chat) else { return XCTFail("expected the API") }
        XCTAssertEqual(p2.id, "anthropic")
        XCTAssertEqual(c2.model, "claude-haiku-5-5", "an empty model is the preset's suggestion")
        XCTAssertEqual(c2.baseUrl, "https://api.anthropic.com/v1")
    }

    func testOpenCodeUsesItsOwnModelElseTheCallersOnlyWhereTranslationIsInForce() {
        var setup = AiSetup.empty
        XCTAssertEqual(resolve(setup, purpose: .translation, callerModel: "a/legacy"), .openCode(model: "a/legacy"))
        XCTAssertEqual(resolve(setup, purpose: .chat, callerModel: "a/legacy"), .openCode(model: "a/legacy"))
        XCTAssertEqual(resolve(setup, purpose: .translation, callerModel: " "), .openCode(model: nil))
        setup.translation = AiModelChoice(providerId: "opencode", model: "b/pinned")
        XCTAssertEqual(resolve(setup, purpose: .translation, callerModel: "a/legacy"), .openCode(model: "b/pinned"))
        setup.chat = .openCodeDefault
        XCTAssertEqual(resolve(setup, purpose: .chat, callerModel: "a/legacy"), .openCode(model: nil), "chat's own choice: OpenCode's default")
    }

    func testAChoiceOfARemovedProviderFallsBackToOpenCode() {
        let setup = AiSetup(providers: [], translation: AiModelChoice(providerId: "gone", model: "m"))
        XCTAssertEqual(resolve(setup, purpose: .translation), .openCode(model: "m"))
    }
}

// MARK: migration + repository

final class AiSetupMigrationTests: XCTestCase {
    func testAnEnabledConfigBecomesTheTranslationProvider() {
        let old = TranslationApiConfig(presetId: "groq", baseUrl: "https://api.groq.com/openai/v1", model: "llama", apiKey: "gk")
        let setup = MigrateTranslationApiConfig()(old)
        XCTAssertEqual(setup.providers, [AiProvider(id: "groq", presetId: "groq", name: "Groq", baseUrl: "https://api.groq.com/openai/v1", apiKey: "gk")])
        XCTAssertEqual(setup.translation, AiModelChoice(providerId: "groq", model: "llama"))
        XCTAssertNil(setup.chat)
    }

    func testASwitchedOffConfigKeepsTheProviderButTranslatesWithOpenCode() {
        let old = TranslationApiConfig(presetId: "custom", baseUrl: "https://llm.example.test/v1", model: "m", apiKey: "k", enabled: false)
        let setup = MigrateTranslationApiConfig()(old)
        XCTAssertEqual(setup.providers.first?.name, "llm.example.test")
        XCTAssertEqual(setup.providers.first?.id, "custom")
        XCTAssertEqual(setup.translation, .openCodeDefault)
        XCTAssertEqual(MigrateTranslationApiConfig()(TranslationApiConfig(presetId: "groq", baseUrl: " ", model: "m")), .empty)
    }

    func testTheRepositoryMigratesTheOldItemOnceAndRemovesIt() async throws {
        let oldJson = #"{"preset":"gemini","baseUrl":"https://g.test/v1","model":"gem","apiKey":"gk","enabled":true}"#
        let store = FakeStore([CredentialKey.translationApi: oldJson])
        let setupLoaded = await CredentialAiSetupRepository(store: store).load().value
        let setup = try XCTUnwrap(setupLoaded)
        XCTAssertEqual(setup.translation, AiModelChoice(providerId: "gemini", model: "gem"))
        let values = await store.values
        XCTAssertNil(values[CredentialKey.translationApi], "the old item goes once the new one is written")
        // A new session reads the new item.
        let againLoaded = await CredentialAiSetupRepository(store: store).load().value
        let again = try XCTUnwrap(againLoaded)
        XCTAssertEqual(again, setup)
    }

    func testNothingSavedIsTheEmptySetupAndWritesNothing() async {
        let store = FakeStore()
        let setup = await CredentialAiSetupRepository(store: store).load().value
        XCTAssertEqual(setup, .empty)
        let values = await store.values
        XCTAssertTrue(values.isEmpty)
    }

    func testSaveRoundTripsEveryProviderAndChoiceAndIsCached() async throws {
        let store = FakeStore(), repo = CredentialAiSetupRepository(store: store)
        let setup = AiSetup(providers: [openai, claude], translation: AiModelChoice(providerId: "openai", model: "gpt-5-mini"),
                            chat: AiModelChoice(providerId: "anthropic", model: ""))
        _ = await repo.save(setup)
        _ = await repo.load(); _ = await repo.load()
        let reads = await store.reads
        XCTAssertEqual(reads, 0, "save primes the cache")
        let freshLoaded = await CredentialAiSetupRepository(store: store).load().value
        let fresh = try XCTUnwrap(freshLoaded)
        XCTAssertEqual(fresh, setup)
        // "Same as translation" is stored as no chat choice.
        _ = await repo.save(AiSetupEditing.chatSameAsTranslation(true, in: setup))
        let sameLoaded = await CredentialAiSetupRepository(store: store).load().value
        let same = try XCTUnwrap(sameLoaded)
        XCTAssertNil(same.chat)
    }

    func testAnUnreadableItemIsAFailureNotAnEmptySetup() async {
        let store = FakeStore([CredentialKey.aiSetup: "not json"])
        guard case .failure = await CredentialAiSetupRepository(store: store).load() else { return XCTFail("expected a failure") }
    }
}

// MARK: routing per purpose

final class RoutingPerPurposeTests: XCTestCase {
    private func routing(_ setup: AiSetup, _ calls: Calls) -> RoutingTranslationService {
        RoutingTranslationService(api: FakeApi(calls: calls), openCode: FakeOpenCode(calls: calls), setup: { setup })
    }

    func testTranslationAndChatRunOnTheirOwnChoices() async {
        let calls = Calls()
        let setup = AiSetup(providers: [openai, claude], translation: AiModelChoice(providerId: "openai", model: "gpt-5-mini"),
                            chat: AiModelChoice(providerId: "anthropic", model: "claude-x"))
        let r = routing(setup, calls)
        _ = await r.translateText(key: "k", text: "t", targetLang: "vi", model: "legacy/m")
        _ = await r.translate(ticketId: "t", source: TicketSource(title: "a", body: "b"), sourceHash: "h", targetLang: "vi", model: nil)
        _ = await r.complete(key: "c", prompt: "p", model: "legacy/m")
        XCTAssertEqual(calls.all, ["api.text openai gpt-5-mini sk-o", "api.translate openai gpt-5-mini sk-o", "api.complete anthropic claude-x sk-a"])
    }

    func testOpenCodeChoicesGetTheirModelOrTheCallers() async {
        let calls = Calls()
        let setup = AiSetup(providers: [openai], translation: .openCodeDefault, chat: AiModelChoice(providerId: "opencode", model: "x/chat"))
        let r = routing(setup, calls)
        _ = await r.translateText(key: "k", text: "t", targetLang: "vi", model: "legacy/m")
        _ = await r.complete(key: "c", prompt: "p", model: "legacy/m")
        XCTAssertEqual(calls.all, ["oc.text legacy/m", "oc.complete x/chat"])
        XCTAssertEqual(r.contentHash(TicketSource(title: "a", body: "b")), "oc", "the cache key does not depend on the backend")
    }

    func testCancelReachesTheBackendTheRunWentTo() async {
        let calls = Calls()
        let gate = AsyncGate()
        let api = SlowApi(calls: calls, gate: gate)
        let r = RoutingTranslationService(api: api, openCode: FakeOpenCode(calls: calls),
                                          setup: { AiSetup(providers: [openai], translation: AiModelChoice(providerId: "openai")) })
        let run = Task { await r.translateText(key: "k1", text: "t", targetLang: "vi", model: nil) }
        await gate.waitUntilEntered()
        await r.cancel("k1")
        await gate.release()
        _ = await run.value
        XCTAssertTrue(calls.all.contains("api.cancel k1"))
        XCTAssertFalse(calls.all.contains("oc.cancel k1"))
    }
}

/// Lets a test hold a fake run in flight until it has cancelled it.
private actor AsyncGate {
    private var entered = false, released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = [], releaseWaiters: [CheckedContinuation<Void, Never>] = []
    func enter() async {
        entered = true; enteredWaiters.forEach { $0.resume() }; enteredWaiters = []
        if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
    }
    func waitUntilEntered() async { if !entered { await withCheckedContinuation { enteredWaiters.append($0) } } }
    func release() { released = true; releaseWaiters.forEach { $0.resume() }; releaseWaiters = [] }
}

private struct SlowApi: ConfiguredTranslationBackend {
    let calls: Calls; let gate: AsyncGate
    func contentHash(_ source: TicketSource) -> String { "api" }
    func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String, config: TranslationApiConfig) async -> Outcome<TranslationRecord> { .failure(.agent("x")) }
    func translateText(key: String, text: String, targetLang: String, config: TranslationApiConfig) async -> Outcome<TextTranslation> {
        await gate.enter(); return .success(TextTranslation("api"))
    }
    func complete(key: String, prompt: String, config: TranslationApiConfig) async -> Outcome<TextTranslation> { .success(TextTranslation("api")) }
    func cancel(_ key: String) async { calls.add("api.cancel \(key)") }
}

// MARK: Anthropic

final class AnthropicEndpointTests: XCTestCase {
    func testChatCompletionsCarryAnthropicHeadersBesideBearer() async throws {
        let http = RecordingHTTP(["choices": [["message": ["content": "Xin chào"]]]])
        let cfg = TranslationApiConfig(presetId: "anthropic", baseUrl: "https://api.anthropic.com/v1", model: "claude-haiku-5-5", apiKey: "sk-a")
        let r = await ApiTranslationService(http: http).translateText(key: "k", text: "Hello", targetLang: "vi", config: cfg)
        XCTAssertEqual(r.value?.text, "Xin chào")
        let req = try XCTUnwrap(http.last)
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-a")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-a")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testOtherEndpointsGetOnlyBearer() async throws {
        let http = RecordingHTTP(["choices": [["message": ["content": "ok"]]]])
        let cfg = TranslationApiConfig(presetId: "openai", baseUrl: "https://api.openai.com/v1", model: "gpt-5-mini", apiKey: "sk-o")
        _ = await ApiTranslationService(http: http).complete(key: "k", prompt: "p", config: cfg)
        let req = try XCTUnwrap(http.last)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-o")
        XCTAssertNil(req.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertNil(req.value(forHTTPHeaderField: "anthropic-version"))
    }

    func testModelListReadsAnthropicsShapeWithItsHeaders() async throws {
        let http = RecordingHTTP(["data": [["id": "claude-sonnet-5", "type": "model", "display_name": "Claude Sonnet 5"],
                                           ["id": "claude-haiku-5-5", "type": "model", "display_name": "Claude Haiku 5.5"]],
                                  "has_more": false, "first_id": "claude-sonnet-5", "last_id": "claude-haiku-5-5"])
        let r = await OpenAIModelCatalogDataSource(http: http).listModels(baseUrl: "https://api.anthropic.com/v1/", apiKey: "sk-a")
        XCTAssertEqual(r.value, ["claude-haiku-5-5", "claude-sonnet-5"])
        let req = try XCTUnwrap(http.last)
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/models?limit=1000")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-a")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testOpenAIsNonChatModelsAreLeftOut() async {
        let http = RecordingHTTP(["data": [["id": "gpt-5-mini"], ["id": "dall-e-3"], ["id": "gpt-image-1"], ["id": "whisper-1"],
                                           ["id": "gpt-4o-realtime-preview"], ["id": "text-embedding-3-small"], ["id": "omni-moderation-latest"]]])
        let r = await OpenAIModelCatalogDataSource(http: http).listModels(baseUrl: "https://api.openai.com/v1", apiKey: "k")
        XCTAssertEqual(r.value, ["gpt-5-mini"])
    }

    func testNewPresetsAreOffered() {
        for id in ["openai", "anthropic", "deepseek", "mistral", "xai", "gemini", "groq", "openrouter", "ollama"] {
            XCTAssertEqual(TranslationApiPreset.byId(id).id, id)
        }
        XCTAssertEqual(TranslationApiPreset.byId("anthropic").baseUrl, "https://api.anthropic.com/v1")
        XCTAssertEqual(TranslationApiPreset.byId("xai").defaultModel, "grok-4")
    }
}
