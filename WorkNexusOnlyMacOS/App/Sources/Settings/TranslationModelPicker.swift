import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// Ported from: lib/features/translation/presentation/widgets/translation_model_picker.dart (per purpose: not in the Flutter app)
/// The model a purpose runs on through OpenCode. Left on OpenCode's default, a broken or queued default silently turns every
/// run into a hang; pinning one makes the choice explicit and changeable without editing `opencode.json`.
struct TranslationModelPicker: View {
    @Environment(\.toasts) private var toasts
    let root: CompositionRoot
    let purpose: AiPurpose
    @State private var models: [String]?

    var body: some View {
        let selected = AiSettingsLogic.openCodeModel(root.aiSetup.setup, purpose: purpose, legacyModel: root.shell.settings.translationModel)
        AiModelPicker(choices: models.map { TranslationSettingsLogic.openCodeModelChoices(selected: selected, models: $0) },
                      selected: selected,
                      labelOf: { $0.isEmpty ? appString("translationModelDefault", "OpenCode default") : $0 },
                      placeholder: "provider/model",
                      note: models?.isEmpty == true
                          ? appString("translationModelListUnavailable", "OpenCode returned no models — check `opencode models` in a terminal.") : nil,
                      onPick: pick)
            .task { models = await root.translation.openCodeCli.listModels() }
    }

    private func pick(_ model: String) {
        let store = root.aiSetup
        let new = AiSetupEditing.choosing(AiModelChoice(providerId: AiModelChoice.openCodeId, model: model), for: purpose, in: store.setup)
        // Translation keeps the older pin (`translationModel`) in step, so its fallback never brings an old model back.
        if purpose == .translation { root.shell.updateSettings { $0.translationModel = model } }
        let toasts = toasts
        Task { await saveAiSetup(new, store: store, toasts: toasts) }
    }
}
