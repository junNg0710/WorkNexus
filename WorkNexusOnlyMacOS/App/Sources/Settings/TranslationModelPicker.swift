import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// Ported from: lib/features/translation/presentation/widgets/translation_model_picker.dart
/// The model ticket translation runs on through OpenCode. Left on OpenCode's default, a broken or queued default silently turns
/// every translation into a hang; pinning one makes the choice explicit and changeable without editing `opencode.json`.
struct TranslationModelPicker: View {
    @Environment(\.appTheme) private var theme
    let root: CompositionRoot
    @State private var models: [String]?

    var body: some View {
        let selected = root.shell.settings.translationModel
        if let models {
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                SearchableDropdownField(items: TranslationSettingsLogic.openCodeModelChoices(selected: selected, models: models), value: selected,
                                        labelOf: { $0.isEmpty ? appString("translationModelDefault", "OpenCode default") : $0 },
                                        searchHint: appString("searchModels", "Search models…"), emptyLabel: appString("noMatches", "No matches")) { m in
                    root.shell.updateSettings { $0.translationModel = m }
                }
                if models.isEmpty {
                    AppInlineNote(appString("translationModelListUnavailable", "OpenCode returned no models — check `opencode models` in a terminal."))
                }
            }
        } else {
            AppInlineSpinner().task { models = await root.translation.openCodeCli.listModels() }
        }
    }
}
