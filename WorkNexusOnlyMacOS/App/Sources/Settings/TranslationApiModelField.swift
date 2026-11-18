import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// Ported from: lib/features/translation/presentation/widgets/translation_api_model_field.dart (per saved provider and
/// purpose: not in the Flutter app)
/// The model a purpose runs on with a saved provider: what the endpoint serves (`GET /models` with the provider's key), the
/// preset's suggestion, or any id typed in — so a provider without a usable listing never blocks the choice.
struct TranslationApiModelField: View {
    @Environment(\.toasts) private var toasts
    let root: CompositionRoot
    let purpose: AiPurpose
    let provider: AiProvider
    @State private var models: [String]?
    @State private var failed = false

    var body: some View {
        let preset = provider.preset, selected = root.aiSetup.setup.choice(for: purpose).model
        let ready = TranslationSettingsLogic.canListModels(baseUrl: provider.baseUrl, apiKey: provider.apiKey, needsKey: preset.needsKey)
        // The empty id is "the preset's suggestion"; a custom endpoint has none.
        let suggested: [String] = preset.defaultModel.isEmpty ? [] : [""]
        let choices: [String]? = !ready || failed ? [] : models.map { suggested + TranslationSettingsLogic.apiModelChoices(selected: selected, models: $0) }
        AiModelPicker(choices: choices, selected: selected,
                      labelOf: { $0.isEmpty ? appFormat("aiModelSuggested", "Suggested (%1$@)", preset.defaultModel) : $0 },
                      placeholder: preset.defaultModel,
                      note: ready && failed ? appString("translationApiModelsLoadFailed", "Couldn't load the model list — type the model name instead") : nil,
                      onPick: pick)
            .task(id: "\(provider.id)|\(provider.baseUrl)|\(provider.apiKey.hashValue)|\(ready)") {
                models = nil; failed = false
                guard ready else { return }
                switch await root.translation.modelCatalog.listModels(baseUrl: provider.baseUrl, apiKey: provider.apiKey) {
                case .success(let list): models = list; failed = list.isEmpty
                case .failure: failed = true
                }
            }
    }

    private func pick(_ model: String) {
        let store = root.aiSetup
        let new = AiSetupEditing.choosing(AiModelChoice(providerId: provider.id, model: model), for: purpose, in: store.setup)
        let toasts = toasts
        Task { await saveAiSetup(new, store: store, toasts: toasts) }
    }
}
