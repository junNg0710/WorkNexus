import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// Ported from: lib/features/translation/presentation/widgets/translation_opencode_key_field.dart
/// The API key OpenCode translates with, for the provider of the chosen model (`opencode/…` → `opencode`). It is written to
/// OpenCode's own credential store, so it is the key the CLI uses. Shows what is saved (masked) and where to get a key.
struct TranslationOpenCodeKeyField: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let root: CompositionRoot
    @State private var key = ""
    @State private var obscure = true
    @State private var saving = false
    @State private var error: String?
    @State private var auth: OpenCodeProviderAuth?

    var body: some View {
        let providerId = openCodeProvider(of: root.shell.settings.translationModel)
        let canSave = !saving && !key.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            TranslationTextField(label: appFormat("translationOpenCodeKey", "API key · %1$@", providerId), text: $key, secure: obscure,
                                 onSubmit: { if canSave { Task { await save(providerId) } } }) {
                AppButton(appString("translationApiGetKey", "Get a key"), kind: .ghost) { _ = openExternally(openCodeKeyUrl(providerId)) }
                AppButton(obscure ? appString("openCodeShowKey", "Show") : appString("openCodeHideKey", "Hide"), kind: .ghost) { obscure.toggle() }
            }
            if let status = status() { AppInlineNote(status) }
            if let error { AppInlineNote(error, isError: true) }
            HStack(spacing: theme.spacing.s8) {
                AppButton(appString("translationApiSave", "Save"), kind: .primary) { Task { await save(providerId) } }.disabled(!canSave)
                if case .saved(_)? = TranslationSettingsLogic.keyStatus(auth) {
                    AppButton(appString("translationApiRemove", "Remove key"), kind: .danger) { Task { await remove(providerId) } }.disabled(saving)
                }
            }
        }
        .task(id: providerId) { await refresh(providerId) }
    }

    /// Null when the store could not be read — the field still works then.
    private func status() -> String? {
        switch TranslationSettingsLogic.keyStatus(auth) {
        case nil: nil
        case .none?: appString("translationOpenCodeKeyNone", "No key saved for this provider yet.")
        case .oauth?: appString("translationOpenCodeKeyOauth", "Signed in through `opencode auth login`. A key typed here replaces that login.")
        case .saved(let preview)?: appFormat("translationOpenCodeKeySaved", "Saved key %1$@ — type a new one to replace it.", preview)
        }
    }

    private func refresh(_ providerId: String) async {
        if case .success(let a) = await root.translation.openCodeKeys.authFor(providerId: providerId) { auth = a } else { auth = nil }
    }

    private func remove(_ providerId: String) async {
        saving = true; error = nil
        switch await root.translation.openCodeKeys.removeApiKey(providerId: providerId) {
        case .success:
            toasts?.show(appFormat("translationOpenCodeKeyRemoved", "Removed the %1$@ key from OpenCode", providerId))
            key = ""; await refresh(providerId)
        case .failure: error = appString("translationOpenCodeKeyRemoveFailed", "Couldn't remove the key.")
        }
        saving = false
    }

    private func save(_ providerId: String) async {
        saving = true; error = nil
        switch await root.translation.openCodeKeys.saveApiKey(providerId: providerId, key: key.trimmingCharacters(in: .whitespaces)) {
        case .success:
            toasts?.show(appFormat("translationOpenCodeKeySaveDone", "Saved the %1$@ key for OpenCode", providerId))
            key = ""; await refresh(providerId)
        case .failure: error = appString("translationApiSaveFailed", "Couldn't save the translation key.")
        }
        saving = false
    }
}
