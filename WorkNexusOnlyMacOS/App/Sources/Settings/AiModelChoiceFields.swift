/// Not in the Flutter app: the provider + model of one purpose (translation, AI in chat).
import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// The provider a purpose runs on (OpenCode or a saved provider) and its model: the endpoint's models for a saved provider,
/// OpenCode's for OpenCode, free text allowed in both. Every pick is saved at once.
struct AiModelChoiceFields: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let root: CompositionRoot
    let purpose: AiPurpose

    var body: some View {
        let setup = root.aiSetup.setup, choice = setup.choice(for: purpose)
        // A choice whose provider is gone runs on OpenCode, so that is what the dropdown shows.
        let provider = choice.isOpenCode ? nil : setup.provider(choice.providerId)
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            FieldBlock(label: appString("translationApiProvider", "Provider")) {
                SearchableDropdownField(items: AiSettingsLogic.choiceIds(setup), value: provider?.id ?? AiModelChoice.openCodeId,
                                        labelOf: { Self.name(of: $0, in: setup) },
                                        searchHint: appString("translationApiProvider", "Provider"), emptyLabel: appString("noMatches", "No matches")) { pick($0) }
            }
            FieldBlock(label: appString("translationApiModel", "Model")) {
                if let provider {
                    TranslationApiModelField(root: root, purpose: purpose, provider: provider).id(provider.id)
                } else {
                    TranslationModelPicker(root: root, purpose: purpose)
                }
            }
        }
    }

    static func name(of id: String, in setup: AiSetup) -> String {
        if id == AiModelChoice.openCodeId { return appString("translationProviderOpenCode", "OpenCode (CLI)") }
        return setup.provider(id)?.name ?? id
    }

    private func pick(_ id: String) {
        let store = root.aiSetup
        let current = store.setup.choice(for: purpose)
        let next = AiSettingsLogic.pick(providerId: id, current: current)
        guard next != current else { return }
        let toasts = toasts
        Task { await saveAiSetup(AiSetupEditing.choosing(next, for: purpose, in: store.setup), store: store, toasts: toasts) }
    }
}

/// AI in chat (✨ summaries, reply ideas, rewrites): the translation choice by default, or a provider + model of its own.
struct AiChatChoiceSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let root: CompositionRoot

    var body: some View {
        let store = root.aiSetup, same = store.setup.chat == nil
        let current = store.backendName(.translation, legacyModel: root.shell.settings.translationModel)
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            SettingsToggleRow(label: appString("aiChatSameAsTranslation", "Same as translation"),
                              hint: same ? appFormat("aiChatSameHint", "AI in chat runs on %1$@.", current) : nil,
                              isOn: same) { on in
                let toasts = toasts
                Task { await saveAiSetup(AiSetupEditing.chatSameAsTranslation(on, in: store.setup), store: store, toasts: toasts) }
            }
            if !same { AiModelChoiceFields(root: root, purpose: .chat) }
        }
    }
}
