import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// Ported from: lib/features/translation/presentation/widgets/translation_api_model_field.dart
/// The model to translate with: a dropdown of what the endpoint serves, or a text field while the list is loading, cannot be
/// fetched yet (no key), or failed — so a provider without a usable listing never blocks saving.
struct TranslationApiModelField: View {
    @Environment(\.appTheme) private var theme
    let root: CompositionRoot
    let baseUrl: String
    let apiKey: String
    let needsKey: Bool
    @Binding var model: String
    let onSubmit: () -> Void
    @State private var models: [String]?
    @State private var failed = false

    var body: some View {
        let ready = TranslationSettingsLogic.canListModels(baseUrl: baseUrl, apiKey: apiKey, needsKey: needsKey)
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            if ready, let models, !models.isEmpty {
                // A saved model the endpoint no longer lists stays in the list, so it is visible (and replaceable).
                FieldBlock(label: appString("translationApiModel", "Model")) {
                    SearchableDropdownField(items: TranslationSettingsLogic.apiModelChoices(selected: model.trimmingCharacters(in: .whitespaces), models: models),
                                            value: model.isEmpty ? nil : model.trimmingCharacters(in: .whitespaces), labelOf: { $0 },
                                            searchHint: appString("searchModels", "Search models…"), emptyLabel: appString("noMatches", "No matches")) { model = $0 }
                }
            } else {
                TranslationTextField(label: appString("translationApiModel", "Model"), text: $model, onSubmit: onSubmit)
                if ready && failed { AppInlineNote(appString("translationApiModelsLoadFailed", "Couldn't load the model list — type the model name instead")) }
            }
        }
        // The list is asked for once the endpoint and key stop changing.
        .task(id: "\(baseUrl.trimmingCharacters(in: .whitespaces))|\(apiKey.trimmingCharacters(in: .whitespaces))|\(ready)") {
            models = nil; failed = false
            guard ready else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            switch await root.translation.modelCatalog.listModels(baseUrl: baseUrl.trimmingCharacters(in: .whitespaces), apiKey: apiKey.trimmingCharacters(in: .whitespaces)) {
            case .success(let list): models = list; failed = list.isEmpty
            case .failure: failed = true
            }
        }
    }
}
