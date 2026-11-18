import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// Ported from: lib/features/translation/presentation/widgets/translation_api_fields.dart (`FieldBlock`, `TranslationTextField`);
/// `AiModelPicker` and `saveAiSetup` are not in the Flutter app.

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

/// The model of a provider choice: a dropdown of what the backend lists, and a field to type any other id instead —
/// providers rename models, and a list can be missing. `choices` nil: still loading; empty: no list, so the field shows.
struct AiModelPicker: View {
    @Environment(\.appTheme) private var theme
    let choices: [String]?
    let selected: String
    let labelOf: (String) -> String
    var placeholder = ""
    /// Shown under the control (why there is no list).
    var note: String?
    let onPick: (String) -> Void
    @State private var typing = false
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            if let choices, !choices.isEmpty, !typing {
                HStack(spacing: theme.spacing.s8) {
                    SearchableDropdownField(items: choices, value: choices.contains(selected) ? selected : nil, labelOf: labelOf,
                                            searchHint: appString("searchModels", "Search models…"), emptyLabel: appString("noMatches", "No matches")) { onPick($0) }
                    AppButton(appString("aiModelTypeOwn", "Type a model"), kind: .ghost) { typed = selected; typing = true }
                }
            } else if choices == nil {
                AppInlineSpinner()
            } else {
                HStack(spacing: theme.spacing.s8) {
                    TranslationTextField(label: appString("aiModelId", "Model id"), text: $typed, prompt: placeholder, onSubmit: apply) {
                        AppButton(appString("aiModelApply", "Apply"), kind: .ghost, action: apply)
                            .disabled(typed.trimmingCharacters(in: .whitespaces) == selected)
                    }
                    if typing {
                        AppButton(appString("aiModelBackToList", "Back to list"), kind: .ghost) { typing = false }
                    }
                }
            }
            if let note { AppInlineNote(note) }
        }
        .onAppear { if typed.isEmpty { typed = selected } }
        .onChange(of: selected) { _, now in typed = now }
    }

    private func apply() {
        let m = typed.trimmingCharacters(in: .whitespaces)
        guard m != selected else { return }
        onPick(m); typing = false
    }
}

/// Saves `new` through the store, telling the user when the credential store refused it.
@MainActor
@discardableResult
func saveAiSetup(_ new: AiSetup, store: AiSetupStore, toasts: AppToastController?) async -> Bool {
    if await store.save(new) { return true }
    toasts?.show(appString("aiSetupSaveFailed", "Couldn't save the AI settings."), kind: .error)
    return false
}
