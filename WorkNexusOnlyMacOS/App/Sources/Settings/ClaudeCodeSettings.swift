/// Not in the Flutter app: Claude Code as a built-in AI provider (the `claude` CLI on the user's own Claude login).
import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// The Claude Code row of the provider list: whether the CLI is there and signed in, and how to fix it when it is not.
struct ClaudeCodeProviderRow: View {
    let root: CompositionRoot
    @State private var status: ClaudeCodeStatus?

    var body: some View {
        AiProviderRow(icon: "sparkle", name: appString("aiClaudeCode", "Claude Code (your Claude login)"), detail: detail) { EmptyView() }
            .task { status = await root.translation.claudeCodeCli.status() }
    }

    private var detail: String {
        switch status {
        case nil: appString("aiClaudeCodeChecking", "Checking the claude command…")
        case .loggedIn: appString("aiClaudeCodeReady", "Built in: the claude CLI with your Claude login — no API key")
        case .loggedOut: appString("aiClaudeCodeLoggedOut", "Signed out — run `claude auth login` in a terminal")
        case .notInstalled: appString("aiClaudeCodeMissing", "Not installed — install Claude Code to use your Claude login")
        }
    }
}

/// The model of a purpose that runs on Claude Code: its default, or the latest Haiku / Sonnet / Opus. Saved at once.
struct ClaudeCodeModelField: View {
    @Environment(\.toasts) private var toasts
    let root: CompositionRoot
    let purpose: AiPurpose

    var body: some View {
        let store = root.aiSetup, selected = store.setup.choice(for: purpose).model
        SearchableDropdownField(items: ClaudeCodeModels.choices(selected: selected), value: selected, labelOf: Self.label(of:),
                                searchHint: appString("translationApiModel", "Model"), emptyLabel: appString("noMatches", "No matches")) { pick($0) }
    }

    static func label(of model: String) -> String {
        switch model {
        case "": appString("aiClaudeCodeDefaultModel", "Claude Code's default")
        case "haiku": appString("aiClaudeCodeHaiku", "Haiku — fastest")
        case "sonnet": appString("aiClaudeCodeSonnet", "Sonnet — balanced")
        case "opus": appString("aiClaudeCodeOpus", "Opus — most capable")
        default: model
        }
    }

    private func pick(_ model: String) {
        let store = root.aiSetup, toasts = toasts
        let next = AiModelChoice(providerId: AiModelChoice.claudeCodeId, model: model)
        guard next != store.setup.choice(for: purpose) else { return }
        Task { await saveAiSetup(AiSetupEditing.choosing(next, for: purpose, in: store.setup), store: store, toasts: toasts) }
    }
}
