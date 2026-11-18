/// Not in the Flutter app: the decisions of the AI provider settings (macOS only).
import XCTest
@testable import FeatureTranslation

private let openai = AiProvider(id: "openai", presetId: "openai", name: "OpenAI", baseUrl: "https://api.openai.com/v1", apiKey: "sk-openai-1234")

final class AiSetupEditingTests: XCTestCase {
    func testAddingGivesUniqueReadableIds() {
        var setup = AiSetup.empty
        let first = AiSetupEditing.adding(openai, to: setup); setup = first.setup
        let second = AiSetupEditing.adding(openai, to: setup); setup = second.setup
        XCTAssertEqual(first.id, "openai"); XCTAssertEqual(second.id, "openai-2")
        XCTAssertEqual(setup.providers.map(\.id), ["openai", "openai-2"])
        XCTAssertEqual(AiSetupEditing.newProviderId(presetId: "opencode", existing: []), "provider", "never the OpenCode id")
    }

    func testAnEditWithoutAKeyKeepsTheSavedOne() {
        let setup = AiSetup(providers: [openai])
        var edit = openai; edit.apiKey = " "; edit.name = "Work OpenAI"
        let updated = AiSetupEditing.updating(edit, in: setup)
        XCTAssertEqual(updated.providers.first?.apiKey, "sk-openai-1234")
        XCTAssertEqual(updated.providers.first?.name, "Work OpenAI")
        edit.apiKey = "sk-new"
        XCTAssertEqual(AiSetupEditing.updating(edit, in: setup).providers.first?.apiKey, "sk-new")
    }

    func testRemovingAProviderInUseFallsBackToOpenCodeAndSaysWhere() {
        let setup = AiSetup(providers: [openai], translation: AiModelChoice(providerId: "openai", model: "gpt-5"),
                            chat: AiModelChoice(providerId: "openai", model: "gpt-5-mini"))
        let (after, fellBack) = AiSetupEditing.removing("openai", from: setup)
        XCTAssertTrue(after.providers.isEmpty)
        XCTAssertEqual(after.translation, .openCodeDefault); XCTAssertEqual(after.chat, .openCodeDefault)
        XCTAssertEqual(fellBack, [.translation, .chat])
        let unused = AiSetupEditing.removing("openai", from: AiSetup(providers: [openai]))
        XCTAssertEqual(unused.fellBack, [])
        // Chat that only follows translation is not reported on its own.
        let following = AiSetupEditing.removing("openai", from: AiSetup(providers: [openai], translation: AiModelChoice(providerId: "openai")))
        XCTAssertEqual(following.fellBack, [.translation]); XCTAssertNil(following.setup.chat)
    }

    func testChatSameAsTranslationSwitch() {
        let setup = AiSetup(providers: [openai], translation: AiModelChoice(providerId: "openai", model: "gpt-5"))
        let own = AiSetupEditing.chatSameAsTranslation(false, in: setup)
        XCTAssertEqual(own.chat, setup.translation, "turning it off starts from what translation uses")
        XCTAssertNil(AiSetupEditing.chatSameAsTranslation(true, in: own).chat)
        let chosen = AiSetupEditing.choosing(.openCodeDefault, for: .chat, in: own)
        XCTAssertEqual(chosen.chat, .openCodeDefault); XCTAssertEqual(chosen.translation, setup.translation)
    }
}

final class AiSettingsLogicTests: XCTestCase {
    func testDisplayNamesAddAShortModel() {
        XCTAssertEqual(AiSettingsLogic.displayName(.openCode(model: nil)), "OpenCode")
        XCTAssertEqual(AiSettingsLogic.displayName(.openCode(model: "opencode/gpt-5-nano")), "OpenCode (gpt-5-nano)")
        let cfg = TranslationApiConfig(presetId: "openai", baseUrl: "u", model: "gpt-5-mini")
        XCTAssertEqual(AiSettingsLogic.displayName(.api(provider: openai, config: cfg)), "OpenAI (gpt-5-mini)")
        var long = cfg; long.model = "meta-llama/llama-3.3-70b-instruct:free"
        XCTAssertEqual(AiSettingsLogic.displayName(.api(provider: openai, config: long)), "OpenAI")
        let setup = AiSetup(providers: [openai], translation: AiModelChoice(providerId: "openai"), chat: .openCodeDefault)
        XCTAssertEqual(AiSettingsLogic.backendName(setup, purpose: .translation, legacyModel: "x/y"), "OpenAI (gpt-5-mini)")
        XCTAssertEqual(AiSettingsLogic.backendName(setup, purpose: .chat, legacyModel: "x/y"), "OpenCode")
    }

    func testHostAndMaskedKey() {
        XCTAssertEqual(AiSettingsLogic.host(of: "https://api.x.ai/v1"), "api.x.ai")
        XCTAssertEqual(AiSettingsLogic.host(of: "localhost:11434/v1"), "localhost")
        XCTAssertNil(AiSettingsLogic.host(of: " "))
        XCTAssertEqual(AiSettingsLogic.maskedKey("sk-openai-1234"), "••••••1234")
        XCTAssertEqual(AiSettingsLogic.maskedKey("short"), "••••••", "a short key shows nothing of itself")
        XCTAssertNil(AiSettingsLogic.maskedKey(""))
    }

    func testTheProviderFormSavesWithANameEndpointAndKey() {
        let claude = TranslationApiPreset.byId("anthropic"), ollama = TranslationApiPreset.byId("ollama")
        XCTAssertTrue(AiSettingsLogic.canSaveProvider(preset: claude, name: "Claude", baseUrl: "u", apiKey: "k", hasSavedKey: false, saving: false))
        XCTAssertFalse(AiSettingsLogic.canSaveProvider(preset: claude, name: "Claude", baseUrl: "u", apiKey: " ", hasSavedKey: false, saving: false))
        XCTAssertTrue(AiSettingsLogic.canSaveProvider(preset: claude, name: "Claude", baseUrl: "u", apiKey: "", hasSavedKey: true, saving: false))
        XCTAssertTrue(AiSettingsLogic.canSaveProvider(preset: ollama, name: "Ollama", baseUrl: "u", apiKey: "", hasSavedKey: false, saving: false))
        XCTAssertFalse(AiSettingsLogic.canSaveProvider(preset: ollama, name: " ", baseUrl: "u", apiKey: "", hasSavedKey: false, saving: false))
        XCTAssertFalse(AiSettingsLogic.canSaveProvider(preset: ollama, name: "O", baseUrl: "u", apiKey: "", hasSavedKey: false, saving: true))
    }

    func testTheFormBuildsTheProvider() {
        let preset = AiSettingsLogic.provider(id: "x", preset: .byId("mistral"), name: "", baseUrl: "", apiKey: " k ")
        XCTAssertEqual(preset, AiProvider(id: "x", presetId: "mistral", name: "Mistral", baseUrl: "https://api.mistral.ai/v1", apiKey: "k"))
        let custom = AiSettingsLogic.provider(id: "y", preset: .custom, name: "", baseUrl: " https://llm.corp.test/v1 ", apiKey: "k")
        XCTAssertEqual(custom.name, "llm.corp.test"); XCTAssertEqual(custom.baseUrl, "https://llm.corp.test/v1")
    }

    func testProviderPickAndOpenCodeModels() {
        let setup = AiSetup(providers: [openai], translation: AiModelChoice(providerId: "openai", model: "gpt-5"))
        XCTAssertEqual(AiSettingsLogic.choiceIds(setup), ["opencode", "claudecode", "openai"])
        XCTAssertEqual(AiSettingsLogic.pick(providerId: "openai", current: setup.translation), setup.translation)
        XCTAssertEqual(AiSettingsLogic.pick(providerId: "opencode", current: setup.translation), .openCodeDefault)
        // Translation on OpenCode without a model of its own shows the legacy pin; chat's own OpenCode choice does not.
        let oc = AiSetup(providers: [], translation: .openCodeDefault, chat: .openCodeDefault)
        XCTAssertEqual(AiSettingsLogic.openCodeModel(oc, purpose: .translation, legacyModel: "a/b"), "a/b")
        XCTAssertEqual(AiSettingsLogic.openCodeModel(oc, purpose: .chat, legacyModel: "a/b"), "")
        XCTAssertEqual(AiSettingsLogic.openCodeKeyModel(setup, legacyModel: "a/b"), "a/b", "OpenAI translates, chat follows")
        let chatOnOpenCode = AiSetupEditing.choosing(AiModelChoice(providerId: "opencode", model: "google/gemini"), for: .chat, in: setup)
        XCTAssertEqual(AiSettingsLogic.openCodeKeyModel(chatOnOpenCode, legacyModel: "a/b"), "google/gemini")
    }
}
