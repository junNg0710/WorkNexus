import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// Ported from: lib/features/translation/presentation/widgets/translation_api_form.dart (+ translation_api_fields.dart)
/// Picks the one backend that translates: the OpenCode CLI, or an OpenAI-compatible endpoint with the user's own key (Gemini,
/// Groq, OpenRouter, a local Ollama, a custom URL). Only the chosen provider's models are offered. Enter in a field saves when
/// the form is complete; "Remove key" forgets the saved API provider.
struct TranslationApiForm: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let root: CompositionRoot
    let loadFailed: Bool
    let onSaved: (TranslationApiConfig?) -> Void
    @State private var saved: TranslationApiConfig?
    @State private var preset: TranslationApiPreset
    @State private var baseUrl: String
    @State private var model: String
    @State private var apiKey: String
    @State private var obscure = true
    @State private var saving = false
    @State private var error: String?

    static let choices = [TranslationApiPreset.openCode] + TranslationApiPreset.all

    init(root: CompositionRoot, saved: TranslationApiConfig?, loadFailed: Bool, onSaved: @escaping (TranslationApiConfig?) -> Void) {
        self.root = root; self.loadFailed = loadFailed; self.onSaved = onSaved
        // A saved key that is switched off means OpenCode is the one translating.
        let p = TranslationSettingsLogic.activePreset(saved)
        let f = TranslationSettingsLogic.fields(for: p, saved: saved)
        _saved = State(initialValue: saved); _preset = State(initialValue: p)
        _baseUrl = State(initialValue: f.baseUrl); _model = State(initialValue: f.model); _apiKey = State(initialValue: f.apiKey)
    }

    static func name(of p: TranslationApiPreset) -> String {
        if p.isOpenCode { return appString("translationProviderOpenCode", "OpenCode (CLI)") }
        return p.id == TranslationApiPreset.custom.id ? appString("translationApiCustom", "Custom (OpenAI-compatible)") : p.name
    }

    private var canSave: Bool { TranslationSettingsLogic.canSave(preset: preset, baseUrl: baseUrl, model: model, apiKey: apiKey, saving: saving) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            if loadFailed { AppInlineNote(appString("translationApiLoadFailed", "Couldn't read the saved translation key."), isError: true) }
            FieldBlock(label: appString("translationApiProvider", "Provider")) {
                SearchableDropdownField(items: Self.choices, value: preset, labelOf: Self.name(of:),
                                        searchHint: appString("translationApiProvider", "Provider"), emptyLabel: appString("noMatches", "No matches")) { pick($0) }
            }
            if preset.isOpenCode {
                FieldBlock(label: appString("translationApiModel", "Model")) { TranslationModelPicker(root: root) }
                TranslationOpenCodeKeyField(root: root)
            } else {
                if preset.id == TranslationApiPreset.custom.id {
                    TranslationTextField(label: appString("translationApiBaseUrl", "API base URL"), text: $baseUrl,
                                         prompt: appString("translationApiBaseUrlHint", "https://api.example.com/v1"), onSubmit: submit)
                }
                if preset.needsKey {
                    TranslationTextField(label: appString("translationApiKey", "API key"), text: $apiKey, secure: obscure, onSubmit: submit) {
                        if let url = preset.keyUrl { AppButton(appString("translationApiGetKey", "Get a key"), kind: .ghost) { _ = openExternally(url) } }
                        AppButton(obscure ? appString("openCodeShowKey", "Show") : appString("openCodeHideKey", "Hide"), kind: .ghost) { obscure.toggle() }
                    }
                }
                TranslationApiModelField(root: root, baseUrl: baseUrl, apiKey: apiKey, needsKey: preset.needsKey, model: $model, onSubmit: submit)
            }
            if let error { AppInlineNote(error, isError: true) }
            if !preset.isOpenCode {
                HStack(spacing: theme.spacing.s8) {
                    AppButton(appString("translationApiSave", "Save"), kind: .primary, action: submit).disabled(!canSave)
                    if saving { AppInlineSpinner() }
                    if saved != nil { AppButton(appString("translationApiRemove", "Remove key"), kind: .ghost) { Task { await remove() } } }
                }
            }
        }
    }

    private func submit() { if canSave { Task { await persist(TranslationApiConfig(presetId: preset.id, baseUrl: baseUrl.trimmingCharacters(in: .whitespaces), model: model.trimmingCharacters(in: .whitespaces), apiKey: apiKey.trimmingCharacters(in: .whitespaces))) } } }

    private func pick(_ p: TranslationApiPreset) {
        let f = TranslationSettingsLogic.fields(for: p, saved: saved)
        preset = p; baseUrl = f.baseUrl; model = f.model; apiKey = f.apiKey; error = nil
        // OpenCode takes over at once (the saved key is kept, switched off); picking the saved provider switches its key back on.
        if let config = TranslationSettingsLogic.configOnPick(preset: p, saved: saved) { Task { await persist(config) } }
    }

    private func persist(_ config: TranslationApiConfig) async {
        saving = true; error = nil
        let inForce = config.enabled ? TranslationApiPreset.byId(config.presetId) : .openCode
        switch await root.translation.apiConfig.save(config) {
        case .success:
            saved = config; onSaved(config)
            toasts?.show(appFormat("translationApiSaved", "Saved — %1$@ now translates", Self.name(of: inForce)))
        case .failure: error = appString("translationApiSaveFailed", "Couldn't save the translation key.")
        }
        saving = false
    }

    private func remove() async {
        _ = await root.translation.apiConfig.clear()
        saved = nil; onSaved(nil); preset = .openCode; apiKey = ""
    }
}

/// A small label over a control.
struct FieldBlock<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            Text(label).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
            content
        }
    }
}

/// A labelled text / secret field with trailing buttons (get a key, show / hide); Enter calls `onSubmit`.
struct TranslationTextField<Trailing: View>: View {
    @Environment(\.appTheme) private var theme
    let label: String
    @Binding var text: String
    var prompt = ""
    var secure = false
    let onSubmit: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        FieldBlock(label: label) {
            HStack(spacing: theme.spacing.s4) {
                Group {
                    if secure { SecureField(prompt, text: $text) } else { TextField(prompt, text: $text) }
                }
                .textFieldStyle(.plain).font(theme.typography.body).onSubmit(onSubmit)
                trailing
            }
            .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control36)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
    }
}

extension TranslationTextField where Trailing == EmptyView {
    init(label: String, text: Binding<String>, prompt: String = "", secure: Bool = false, onSubmit: @escaping () -> Void) {
        self.init(label: label, text: text, prompt: prompt, secure: secure, onSubmit: onSubmit) { EmptyView() }
    }
}
