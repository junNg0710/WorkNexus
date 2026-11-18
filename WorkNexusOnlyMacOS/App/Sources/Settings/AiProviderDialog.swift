/// Not in the Flutter app: adds or edits one saved AI provider.
import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// The preset (only when adding), a name, the base URL (custom endpoints), the API key with "Get a key" / "Show", and
/// "Test", which lists the endpoint's models and reports whether that worked. Editing leaves the key empty to keep the saved
/// one. The models themselves are picked under Translation / AI in chat.
struct AiProviderDialog: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let root: CompositionRoot
    let editing: AiProvider?
    let onClose: () -> Void
    @State private var preset: TranslationApiPreset
    @State private var name: String
    @State private var baseUrl: String
    @State private var apiKey = ""
    @State private var obscure = true
    @State private var saving = false
    @State private var error: String?
    @State private var test = AiProviderDialogTestState.idle

    init(root: CompositionRoot, editing: AiProvider?, onClose: @escaping () -> Void) {
        self.root = root; self.editing = editing; self.onClose = onClose
        let p = editing?.preset ?? TranslationApiPreset.all[0]
        _preset = State(initialValue: p)
        _name = State(initialValue: editing?.name ?? Self.defaultName(p))
        _baseUrl = State(initialValue: editing?.baseUrl ?? p.baseUrl)
    }

    static func presetName(_ p: TranslationApiPreset) -> String {
        p.id == TranslationApiPreset.custom.id ? appString("translationApiCustom", "Custom (OpenAI-compatible)") : p.name
    }

    private static func defaultName(_ p: TranslationApiPreset) -> String { p.id == TranslationApiPreset.custom.id ? "" : p.name }
    private var isCustom: Bool { preset.id == TranslationApiPreset.custom.id }
    private var savedKey: String { editing?.apiKey ?? "" }
    /// What a test or a save uses: the key typed, else the saved one.
    private var effectiveKey: String { apiKey.trimmingCharacters(in: .whitespaces).isEmpty ? savedKey : apiKey.trimmingCharacters(in: .whitespaces) }
    private var draft: AiProvider { AiSettingsLogic.provider(id: editing?.id ?? "", preset: preset, name: name, baseUrl: baseUrl, apiKey: apiKey) }
    private var canSave: Bool {
        let d = draft
        return AiSettingsLogic.canSaveProvider(preset: preset, name: d.name, baseUrl: d.baseUrl, apiKey: apiKey,
                                               hasSavedKey: !savedKey.isEmpty, saving: saving)
    }
    private var canTest: Bool {
        test != .running && TranslationSettingsLogic.canListModels(baseUrl: draft.baseUrl, apiKey: effectiveKey, needsKey: preset.needsKey)
    }

    var body: some View {
        let title = editing.map { appFormat("aiProviderEditTitle", "Edit %1$@", $0.name) } ?? appString("aiProviderAddTitle", "Add AI provider")
        AppDialogFrame(title: title, leadingIcon: "sparkles", maxWidth: theme.sizes.dialogMd, onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                if editing == nil {
                    FieldBlock(label: appString("translationApiProvider", "Provider")) {
                        SearchableDropdownField(items: TranslationApiPreset.all, value: preset, labelOf: Self.presetName,
                                                searchHint: appString("translationApiProvider", "Provider"), emptyLabel: appString("noMatches", "No matches")) { pick($0) }
                    }
                }
                TranslationTextField(label: appString("aiProviderName", "Name"), text: $name,
                                     prompt: isCustom ? (AiSettingsLogic.host(of: baseUrl) ?? "") : preset.name, onSubmit: submit)
                if isCustom {
                    TranslationTextField(label: appString("translationApiBaseUrl", "API base URL"), text: $baseUrl,
                                         prompt: appString("translationApiBaseUrlHint", "https://api.example.com/v1"), onSubmit: submit)
                }
                if preset.needsKey {
                    TranslationTextField(label: appString("translationApiKey", "API key"), text: $apiKey,
                                         prompt: AiSettingsLogic.maskedKey(savedKey).map { appFormat("aiProviderKeepKey", "Leave empty to keep %1$@", $0) } ?? "",
                                         secure: obscure, onSubmit: submit) {
                        if let url = preset.keyUrl { AppButton(appString("translationApiGetKey", "Get a key"), kind: .ghost) { _ = openExternally(url) } }
                        AppButton(obscure ? appString("openCodeShowKey", "Show") : appString("openCodeHideKey", "Hide"), kind: .ghost) { obscure.toggle() }
                    }
                }
                HStack(spacing: theme.spacing.s8) {
                    AppButton(appString("aiProviderTest", "Test"), systemImage: "bolt.horizontal", kind: .secondary) { Task { await runTest() } }
                        .disabled(!canTest)
                    TestStatus(state: test)
                }
                if let error { AppInlineNote(error, isError: true) }
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        } actions: {
            Spacer(minLength: 0)
            if saving { AppInlineSpinner() }
            AppButton(appString("cancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(editing == nil ? appString("aiProviderAddAction", "Add") : appString("save", "Save"), kind: .primary, action: submit)
                .disabled(!canSave)
        }
        // A changed endpoint or key makes the last test result stale.
        .onChange(of: "\(preset.id)|\(baseUrl)|\(apiKey.hashValue)") { _, _ in if test != .running { test = .idle } }
    }

    private func pick(_ p: TranslationApiPreset) {
        // A name the user did not change follows the preset.
        if name.trimmingCharacters(in: .whitespaces).isEmpty || name == Self.defaultName(preset) { name = Self.defaultName(p) }
        preset = p; baseUrl = p.baseUrl; error = nil
    }

    private func runTest() async {
        test = .running
        switch await root.translation.modelCatalog.listModels(baseUrl: draft.baseUrl, apiKey: effectiveKey) {
        case .success(let models): test = .ok(models.count)
        case .failure(let f): test = .failed(f.message)
        }
    }

    private func submit() {
        guard canSave else { return }
        Task { await save() }
    }

    private func save() async {
        saving = true; error = nil
        let store = root.aiSetup, provider = draft
        let new = editing == nil ? AiSetupEditing.adding(provider, to: store.setup).setup : AiSetupEditing.updating(provider, in: store.setup)
        if await store.save(new) {
            toasts?.show(editing == nil
                         ? appFormat("aiProviderAdded", "Added %1$@ — pick it under Translation or AI in chat", provider.name)
                         : appFormat("aiProviderSaved", "Saved %1$@", provider.name))
            onClose()
        } else {
            error = appString("aiSetupSaveFailed", "Couldn't save the AI settings.")
        }
        saving = false
    }
}

/// Where "Test" stands: not run (or stale), running, how many models the endpoint listed, or why it failed.
private enum AiProviderDialogTestState: Equatable { case idle, running, ok(Int), failed(String) }

/// The result of "Test", beside its button.
private struct TestStatus: View {
    @Environment(\.appTheme) private var theme
    let state: AiProviderDialogTestState

    var body: some View {
        switch state {
        case .idle: EmptyView()
        case .running: AppInlineSpinner()
        case .ok(let count):
            Label(appFormat("aiProviderTestOk", "Connected — %1$@ models", "\(count)"), systemImage: "checkmark.circle.fill")
                .font(theme.typography.caption).foregroundStyle(theme.colors.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(theme.typography.caption).foregroundStyle(theme.colors.red)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
