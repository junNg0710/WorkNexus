/// Ported from: lib/features/translation/presentation/widgets/{translation_settings_card,translation_api_form,
/// translation_model_picker,translation_api_model_field}.dart (the decisions the widgets make)
import CoreDomain

/// What the translation settings show and decide, apart from drawing it.
public enum TranslationSettingsLogic {
    /// The collapsed card's line: `Tiếng Việt · Google Gemini`.
    public static func summary(languageName: String, backendName: String) -> String { "\(languageName) · \(backendName)" }

    /// The entries of the OpenCode model picker: its own default (empty id), every model the CLI reports, and a pinned model
    /// the CLI no longer lists — kept visible (and replaceable) rather than silently disappearing.
    public static func openCodeModelChoices(selected: String, models: [String]) -> [String] {
        [""] + models + (!selected.isEmpty && !models.contains(selected) ? [selected] : [])
    }

    /// The entries of the API model dropdown: what the endpoint serves, with a saved model it no longer lists first.
    public static func apiModelChoices(selected: String, models: [String]) -> [String] {
        (!selected.isEmpty && !models.contains(selected) ? [selected] : []) + models
    }

    /// Whether the endpoint's model list can be asked for: it needs a base URL, and a key when the provider uses one.
    public static func canListModels(baseUrl: String, apiKey: String, needsKey: Bool) -> Bool {
        let url = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines), key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !(url.isEmpty || (needsKey && key.isEmpty))
    }

    /// The saved OpenCode key's status line; nil when the store could not be read.
    public enum KeyStatus: Equatable, Sendable { case none, oauth, saved(preview: String) }
    public static func keyStatus(_ auth: OpenCodeProviderAuth?) -> KeyStatus? {
        guard let auth else { return nil }
        if !auth.linked { return KeyStatus.none }
        return auth.keyPreview.map { .saved(preview: $0) } ?? .oauth
    }
}
