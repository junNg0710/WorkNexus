import CoreDomain
import CoreUI
import FeatureTranslation
import SharedKit
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/translation_footer.dart (+ core/widgets/translation_language_control.dart)
/// The sticky footer under the translation tab: Translate / Retry / Retranslate, Cancel while a run is going, the machine
/// translation note and the target-language control.
struct TranslationFooterView: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    let hub: TranslationHub
    let shell: ShellModel
    @State private var model: TranslationTabModel

    init(ticket: Ticket, hub: TranslationHub, shell: ShellModel) {
        self.ticket = ticket; self.hub = hub; self.shell = shell
        _model = State(initialValue: hub.model(for: ticket.id))
    }

    var body: some View {
        let state = model.state(ticket)
        let loading = state == .loading
        HStack(spacing: theme.spacing.s12) {
            AppButton(label(state), kind: state == .error ? .danger : (state == .none || loading ? .primary : .secondary)) { model.translate(ticket) }
                .disabled(loading).opacity(loading ? 0.7 : 1)
            // A run can outlast the user's patience, so give them a way out instead of only the hard timeout.
            if loading { AppButton(appString("cancel", "Cancel"), kind: .ghost) { model.cancel() } }
            Text(appString("machineTranslationNote", "Machine translation · review before relying on it"))
                .font(theme.typography.caption).foregroundStyle(theme.colors.tx3).lineSpacing(theme.spacing.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
            TranslationLanguageControl(value: shell.settings.translationLang) { v in shell.updateSettings { $0.translationLang = v } }
                .help(appString("translationLanguage", "Translation language"))
        }
        .padding(.horizontal, theme.spacing.s20).padding(.vertical, theme.spacing.s12)
        .background(theme.colors.panel)
        .overlay(alignment: .top) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
        .task { model.start() }
    }

    private func label(_ state: TranslationState) -> String {
        switch state {
        // The strings name the engine since the upstream sync; this port translates with OpenCode only.
        case .loading: appFormat("translating", "Translating with %1$@…", "OpenCode")
        case .error: appString("retry", "Retry")
        case .none: appFormat("translate", "Translate with %1$@", "OpenCode")
        default: appFormat("retranslate", "Re-translate with %1$@", "OpenCode")
        }
    }
}

/// A compact picker for the translation target language (flag + native name).
struct TranslationLanguageControl: View {
    @Environment(\.appTheme) private var theme
    let value: String
    let onChange: (String) -> Void

    var body: some View {
        let selected = translationLanguage(for: value)
        Menu {
            ForEach(translationLanguages, id: \.code) { lang in
                Button { onChange(lang.code) } label: { Label("\(lang.flag)  \(lang.nativeName)", systemImage: lang.code == selected.code ? "checkmark" : "") }
            }
        } label: {
            HStack(spacing: theme.spacing.s4) {
                Text(selected.flag).font(theme.typography.label)
                Text(selected.nativeName).font(theme.typography.label).foregroundStyle(theme.colors.tx)
                Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx2)
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}
