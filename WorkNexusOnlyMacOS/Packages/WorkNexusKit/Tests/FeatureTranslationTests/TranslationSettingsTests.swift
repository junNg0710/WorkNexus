/// Ported from: lib/core/widgets/opencode_not_linked_dialog.dart (`ensureOpenCodeLinked`) and the decisions of
/// lib/features/translation/presentation/widgets/{translation_settings_card,translation_api_form,translation_model_picker,
/// translation_api_model_field,translation_opencode_key_field}.dart
import CoreDomain
import XCTest
@testable import FeatureTranslation

private final class FakeSetupRepo: AiSetupRepository, @unchecked Sendable {
    var setup = AiSetup.empty
    var fails = false
    func load() async -> Outcome<AiSetup> { fails ? .failure(.storage("keychain")) : .success(setup) }
    func save(_ setup: AiSetup) async -> Outcome<Void> { self.setup = setup; return .success(()) }
}

private struct FakeCli: OpenCodeCli {
    var authed: Bool
    func hasAuthenticatedProvider() async -> Bool { authed }
    func listModels() async -> [String] { [] }
}

private let gemini = AiProvider(id: "gemini", presetId: "gemini", name: "Google Gemini", baseUrl: "https://g.example/v1", apiKey: "k")

final class CheckTranslationReadyTests: XCTestCase {
    func testAUsableProviderIsEnoughWithoutOpenCode() async {
        let repo = FakeSetupRepo(); repo.setup = AiSetup(providers: [gemini], translation: AiModelChoice(providerId: "gemini", model: "m"))
        let check = CheckTranslationReady(setup: repo, cli: FakeCli(authed: false))
        let viaKey = await check.usesApiProvider(), ready = await check()
        XCTAssertTrue(viaKey); XCTAssertTrue(ready)
    }

    func testOpenCodeChoiceNeedsAnOpenCodeLogin() async {
        let repo = FakeSetupRepo(); repo.setup = AiSetup(providers: [gemini], translation: .openCodeDefault)
        let linked = CheckTranslationReady(setup: repo, cli: FakeCli(authed: true))
        let unlinked = CheckTranslationReady(setup: repo, cli: FakeCli(authed: false))
        let a = await linked.usesApiProvider(), b = await linked(), c = await unlinked.readiness()
        XCTAssertFalse(a); XCTAssertTrue(b); XCTAssertEqual(c, .openCodeNotLinked)
    }

    func testNothingConfiguredOrAnUnreadableStoreIsNotReady() async {
        let repo = FakeSetupRepo()
        let none = await CheckTranslationReady(setup: repo, cli: FakeCli(authed: false))()
        XCTAssertFalse(none)
        repo.fails = true
        let unreadable = await CheckTranslationReady(setup: repo, cli: FakeCli(authed: false))()
        XCTAssertFalse(unreadable)
    }

    func testReadinessIsPerPurpose() async {
        var keyless = gemini; keyless.id = "nokey"; keyless.apiKey = ""
        let repo = FakeSetupRepo()
        repo.setup = AiSetup(providers: [gemini, keyless], translation: AiModelChoice(providerId: "gemini"),
                             chat: AiModelChoice(providerId: "nokey"))
        let check = CheckTranslationReady(setup: repo, cli: FakeCli(authed: false))
        let translation = await check.readiness(.translation), chat = await check.readiness(.chat)
        XCTAssertEqual(translation, .ready)
        XCTAssertEqual(chat, .providerNotUsable(name: "Google Gemini"))
        // Chat on OpenCode while translation uses the key: only chat needs the CLI login.
        repo.setup.chat = .openCodeDefault
        let chatOnOpenCode = await check.readiness(.chat), stillReady = await check(.translation)
        XCTAssertEqual(chatOnOpenCode, .openCodeNotLinked)
        XCTAssertTrue(stillReady)
        // Same as translation: chat is ready whenever translation is.
        repo.setup.chat = nil
        let same = await check(.chat)
        XCTAssertTrue(same)
    }

    func testAKeylessPresetIsUsableAndAProviderWithoutModelIsNot() async {
        let ollama = AiProvider(id: "ollama", presetId: "ollama", name: "Ollama", baseUrl: "http://localhost:11434/v1")
        let custom = AiProvider(id: "custom", presetId: "custom", name: "Mine", baseUrl: "https://x.test/v1", apiKey: "k")
        let repo = FakeSetupRepo()
        repo.setup = AiSetup(providers: [ollama, custom], translation: AiModelChoice(providerId: "ollama"), chat: AiModelChoice(providerId: "custom"))
        let check = CheckTranslationReady(setup: repo, cli: FakeCli(authed: false))
        let a = await check(.translation), b = await check.readiness(.chat)
        XCTAssertTrue(a, "Ollama needs no key and has a default model")
        XCTAssertEqual(b, .providerNotUsable(name: "Mine"), "a custom endpoint has no default model")
    }
}

final class TranslationSettingsLogicTests: XCTestCase {
    func testSummary() {
        XCTAssertEqual(TranslationSettingsLogic.summary(languageName: "Tiếng Việt", backendName: "Google Gemini"), "Tiếng Việt · Google Gemini")
    }

    func testModelChoicesKeepAPinnedModelTheListNoLongerHas() {
        XCTAssertEqual(TranslationSettingsLogic.openCodeModelChoices(selected: "", models: ["a/x", "b/y"]), ["", "a/x", "b/y"])
        XCTAssertEqual(TranslationSettingsLogic.openCodeModelChoices(selected: "gone/z", models: ["a/x"]), ["", "a/x", "gone/z"])
        XCTAssertEqual(TranslationSettingsLogic.openCodeModelChoices(selected: "", models: []), [""])
        XCTAssertEqual(TranslationSettingsLogic.apiModelChoices(selected: "old", models: ["n1", "n2"]), ["old", "n1", "n2"])
        XCTAssertEqual(TranslationSettingsLogic.apiModelChoices(selected: "n2", models: ["n1", "n2"]), ["n1", "n2"])
    }

    func testTheModelListIsAskedForOnlyWithAnEndpointAndAKeyWhenNeeded() {
        XCTAssertFalse(TranslationSettingsLogic.canListModels(baseUrl: " ", apiKey: "k", needsKey: true))
        XCTAssertFalse(TranslationSettingsLogic.canListModels(baseUrl: "https://x", apiKey: " ", needsKey: true))
        XCTAssertTrue(TranslationSettingsLogic.canListModels(baseUrl: "https://x", apiKey: "", needsKey: false))
        XCTAssertTrue(TranslationSettingsLogic.canListModels(baseUrl: "https://x", apiKey: "k", needsKey: true))
    }

    func testKeyStatus() {
        XCTAssertNil(TranslationSettingsLogic.keyStatus(nil))
        XCTAssertEqual(TranslationSettingsLogic.keyStatus(.none), .none)
        XCTAssertEqual(TranslationSettingsLogic.keyStatus(OpenCodeProviderAuth(linked: true)), .oauth)
        XCTAssertEqual(TranslationSettingsLogic.keyStatus(OpenCodeProviderAuth(linked: true, keyPreview: "••••a1b2")), .saved(preview: "••••a1b2"))
    }
}
