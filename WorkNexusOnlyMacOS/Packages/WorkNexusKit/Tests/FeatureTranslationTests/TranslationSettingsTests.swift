/// Ported from: lib/core/widgets/opencode_not_linked_dialog.dart (`ensureOpenCodeLinked`) and the decisions of
/// lib/features/translation/presentation/widgets/{translation_settings_card,translation_api_form,translation_model_picker,
/// translation_api_model_field,translation_opencode_key_field}.dart
import CoreDomain
import XCTest
@testable import FeatureTranslation

private final class FakeConfigRepo: TranslationApiConfigRepository, @unchecked Sendable {
    var config: TranslationApiConfig?
    var fails = false
    func load() async -> Outcome<TranslationApiConfig?> { fails ? .failure(.storage("keychain")) : .success(config) }
    func save(_ config: TranslationApiConfig) async -> Outcome<Void> { self.config = config; return .success(()) }
    func clear() async -> Outcome<Void> { config = nil; return .success(()) }
}

private struct FakeCli: OpenCodeCli {
    var authed: Bool
    func hasAuthenticatedProvider() async -> Bool { authed }
    func listModels() async -> [String] { [] }
}

private let usable = TranslationApiConfig(presetId: "gemini", baseUrl: "https://g.example/v1", model: "m", apiKey: "k")

final class CheckTranslationReadyTests: XCTestCase {
    func testAUsableApiKeyIsEnoughWithoutOpenCode() async {
        let repo = FakeConfigRepo(); repo.config = usable
        let check = CheckTranslationReady(apiConfig: repo, cli: FakeCli(authed: false))
        let viaKey = await check.translatesWithApiKey(), ready = await check()
        XCTAssertTrue(viaKey); XCTAssertTrue(ready)
    }

    func testASwitchedOffKeyFallsBackToOpenCodeLogin() async {
        let repo = FakeConfigRepo(); repo.config = usable; repo.config?.enabled = false
        let linked = CheckTranslationReady(apiConfig: repo, cli: FakeCli(authed: true))
        let unlinked = CheckTranslationReady(apiConfig: repo, cli: FakeCli(authed: false))
        let a = await linked.translatesWithApiKey(), b = await linked(), c = await unlinked()
        XCTAssertFalse(a); XCTAssertTrue(b); XCTAssertFalse(c)
    }

    func testNothingConfiguredOrAnUnreadableStoreIsNotReady() async {
        let repo = FakeConfigRepo()
        let none = await CheckTranslationReady(apiConfig: repo, cli: FakeCli(authed: false))()
        XCTAssertFalse(none)
        repo.fails = true
        let unreadable = await CheckTranslationReady(apiConfig: repo, cli: FakeCli(authed: false))()
        XCTAssertFalse(unreadable)
    }
}

final class TranslationSettingsLogicTests: XCTestCase {
    func testActivePresetAndSummary() {
        XCTAssertEqual(TranslationSettingsLogic.activePreset(nil), .openCode)
        XCTAssertEqual(TranslationSettingsLogic.activePreset(usable).id, "gemini")
        var off = usable; off.enabled = false
        XCTAssertEqual(TranslationSettingsLogic.activePreset(off), .openCode)
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

    func testSavingNeedsEndpointModelAndKey() {
        let gemini = TranslationApiPreset.byId("gemini"), ollama = TranslationApiPreset.byId("ollama")
        XCTAssertTrue(TranslationSettingsLogic.canSave(preset: gemini, baseUrl: "u", model: "m", apiKey: "k", saving: false))
        XCTAssertFalse(TranslationSettingsLogic.canSave(preset: gemini, baseUrl: "u", model: "m", apiKey: " ", saving: false))
        XCTAssertTrue(TranslationSettingsLogic.canSave(preset: ollama, baseUrl: "u", model: "m", apiKey: "", saving: false))
        XCTAssertFalse(TranslationSettingsLogic.canSave(preset: ollama, baseUrl: "u", model: "", apiKey: "", saving: false))
        XCTAssertFalse(TranslationSettingsLogic.canSave(preset: ollama, baseUrl: "u", model: "m", apiKey: "", saving: true))
    }

    func testPickingRestoresTheSavedProvidersFieldsAndSwitchesItBackOn() {
        var saved = usable
        let gemini = TranslationApiPreset.byId("gemini"), groq = TranslationApiPreset.byId("groq")
        let restored = TranslationSettingsLogic.fields(for: gemini, saved: saved)
        XCTAssertEqual(restored.model, "m"); XCTAssertEqual(restored.apiKey, "k")
        let other = TranslationSettingsLogic.fields(for: groq, saved: saved)
        XCTAssertEqual(other.model, groq.defaultModel); XCTAssertEqual(other.apiKey, "")
        // OpenCode takes over at once, the key kept but off; picking the saved provider again turns it on.
        let off = TranslationSettingsLogic.configOnPick(preset: .openCode, saved: saved)
        XCTAssertEqual(off?.enabled, false); XCTAssertEqual(off?.apiKey, "k")
        saved.enabled = false
        XCTAssertEqual(TranslationSettingsLogic.configOnPick(preset: gemini, saved: saved)?.enabled, true)
        XCTAssertNil(TranslationSettingsLogic.configOnPick(preset: groq, saved: saved))
        XCTAssertNil(TranslationSettingsLogic.configOnPick(preset: .openCode, saved: nil))
    }

    func testKeyStatus() {
        XCTAssertNil(TranslationSettingsLogic.keyStatus(nil))
        XCTAssertEqual(TranslationSettingsLogic.keyStatus(.none), .none)
        XCTAssertEqual(TranslationSettingsLogic.keyStatus(OpenCodeProviderAuth(linked: true)), .oauth)
        XCTAssertEqual(TranslationSettingsLogic.keyStatus(OpenCodeProviderAuth(linked: true, keyPreview: "••••a1b2")), .saved(preview: "••••a1b2"))
    }
}
