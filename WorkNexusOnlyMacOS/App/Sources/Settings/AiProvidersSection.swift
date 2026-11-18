/// Not in the Flutter app: the list of AI providers (OpenCode built in, plus every endpoint saved with a key).
import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// OpenCode (with the key of the provider it runs on) and each saved provider — name, host, masked key, Edit, Remove — and
/// "Add provider". Removing a provider that translation or AI in chat uses moves that choice to OpenCode, and says so.
struct AiProvidersSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let root: CompositionRoot
    @State private var editing: AiProviderEdit?

    var body: some View {
        let setup = root.aiSetup.setup
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            AiProviderRow(icon: "terminal", name: appString("translationProviderOpenCode", "OpenCode (CLI)"),
                          detail: appString("aiOpenCodeBuiltIn", "Built in: the opencode CLI, with its own login and models")) { EmptyView() }
            TranslationOpenCodeKeyField(root: root, model: AiSettingsLogic.openCodeKeyModel(setup, legacyModel: root.shell.settings.translationModel))
            ClaudeCodeProviderRow(root: root)
            ForEach(setup.providers) { p in
                AiProviderRow(icon: "key", name: p.name, detail: Self.detail(of: p)) {
                    AppButton(appString("edit", "Edit"), kind: .ghost) { editing = AiProviderEdit(provider: p) }
                    AppButton(appString("aiProviderRemove", "Remove"), kind: .danger) { Task { await remove(p) } }
                }
            }
            HStack {
                AppButton(appString("aiProviderAdd", "Add provider"), systemImage: "plus", kind: .secondary) { editing = AiProviderEdit(provider: nil) }
            }
        }
        .appDialog(item: $editing) { e in
            AiProviderDialog(root: root, editing: e.provider) { editing = nil }
        }
    }

    /// `api.openai.com · ••••••a1b2`, or `localhost · No key` for an endpoint without one.
    private static func detail(of p: AiProvider) -> String {
        let host = AiSettingsLogic.host(of: p.baseUrl) ?? p.baseUrl
        return "\(host) · \(AiSettingsLogic.maskedKey(p.apiKey) ?? appString("aiProviderNoKey", "No key"))"
    }

    private func remove(_ p: AiProvider) async {
        let store = root.aiSetup
        let (new, fellBack) = AiSetupEditing.removing(p.id, from: store.setup)
        guard await saveAiSetup(new, store: store, toasts: toasts) else { return }
        let text = switch (fellBack.contains(.translation), fellBack.contains(.chat)) {
        case (true, true): appFormat("aiProviderRemovedBothFallback", "Removed %1$@ — translation and AI in chat now use OpenCode", p.name)
        case (true, false): appFormat("aiProviderRemovedTranslationFallback", "Removed %1$@ — translation now uses OpenCode", p.name)
        case (false, true): appFormat("aiProviderRemovedChatFallback", "Removed %1$@ — AI in chat now uses OpenCode", p.name)
        case (false, false): appFormat("aiProviderRemoved", "Removed %1$@", p.name)
        }
        toasts?.show(text, kind: fellBack.isEmpty ? .success : .warning)
    }
}

/// The add / edit dialog's subject: nil adds a provider.
struct AiProviderEdit: Identifiable {
    let id = UUID()
    let provider: AiProvider?
}

/// One provider line: an icon, its name and a detail line, and trailing actions.
struct AiProviderRow<Actions: View>: View {
    @Environment(\.appTheme) private var theme
    let icon: String
    let name: String
    let detail: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: theme.spacing.s10) {
            Image(systemName: icon).font(.system(size: theme.sizes.icon18)).foregroundStyle(theme.colors.tx2)
                .frame(width: theme.sizes.icon24)
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text(name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                Text(detail).font(theme.typography.caption).foregroundStyle(theme.colors.tx3).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: theme.spacing.s8)
            actions
        }
        .padding(theme.spacing.s10)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}
