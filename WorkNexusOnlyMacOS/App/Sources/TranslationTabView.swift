import CoreDomain
import CoreUI
import FeatureTranslation
import SharedKit
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/translation_tab.dart
/// The "Vietnamese" tab — the translation record and its lifecycle: an empty state, a loading skeleton, the outdated and failure
/// banners, then the translated title and the "Description" section (Markdown, inline images through the ticket's account), and
/// the "via OpenCode" label when it is current.
struct TranslationTabView: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    let layout: DetailLayout
    let hub: TranslationHub
    let shell: ShellModel
    @State private var model: TranslationTabModel

    init(ticket: Ticket, layout: DetailLayout, hub: TranslationHub, shell: ShellModel) {
        self.ticket = ticket; self.layout = layout; self.hub = hub; self.shell = shell
        _model = State(initialValue: hub.model(for: ticket.id))
    }

    private var images: BodyImageHooks {
        let t = ticket, detail = shell.detail
        let path: String? = { if case .gitlabItem(let g)? = t.providerEntity { g.projectPath } else { nil } }()
        let type = t.providerType, base = detail.account(of: t)?.baseUrl
        // The translated body carries the original's inline-image links, so it gets the same "open in browser" fallback.
        return BodyImageHooks(loader: { url in await detail.fetchImage(t, url) },
                              fallbackUrl: { providerImageWebUrl(providerType: type, baseUrl: base, projectPath: path, rawUrl: $0) },
                              onOpenImage: { url in _ = await MainActor.run { openExternally(url) } })
    }

    var body: some View {
        let state = model.state(ticket), record = model.record
        let lang = translationLanguage(for: shell.settings.translationLang)
        DetailScrollBody(layout: layout) {
            VStack(alignment: state == .none ? .center : .leading, spacing: 0) {
                if state == .none { TranslationEmptyState(flag: lang.flag, language: lang.nativeName) }
                if state == .loading { TranslationLoadingState() }
                if state == .outdated {
                    TranslationBanner(text: appString("translationOutdatedBanner", "Original changed since last translation. Showing the earlier version."), hue: theme.colors.amber)
                }
                if state == .error {
                    TranslationBanner(text: model.failure.map { appFormat("translationFailedWithReason", "Translation failed — %1$@", $0) }
                                      ?? appString("translationFailed", "Translation failed"), hue: theme.colors.red)
                }
                if (state == .done || state == .outdated), let record {
                    TranslatedRecord(record: record, ticket: ticket, images: images).opacity(state == .outdated ? 0.62 : 1)
                    if state == .done {
                        HStack(spacing: theme.spacing.s6) {
                            Circle().fill(theme.colors.green).frame(width: theme.spacing.s6, height: theme.spacing.s6)
                            Text("\(appString("translated", "Translated")) · via OpenCode").font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
                        }
                        .padding(.top, theme.spacing.s16)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: state == .none ? .center : .leading)
        }
        .task { model.start() }
    }
}

private struct TranslationEmptyState: View {
    @Environment(\.appTheme) private var theme
    let flag: String
    let language: String

    var body: some View {
        VStack(spacing: theme.spacing.s8) {
            Text(flag).font(theme.typography.display).padding(.top, theme.spacing.s24)
            Text(appString("notTranslated", "Not translated")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
            Text(appFormat("runOpenCodeToTranslate", "Run OpenCode to generate a %1$@ version.", language))
                .font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2).multilineTextAlignment(.center)
        }
    }
}

private struct TranslationLoadingState: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            HStack(spacing: theme.spacing.s8) {
                ProgressView().controlSize(.small)
                Text(appString("translating", "Translating with OpenCode…")).font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx)
            }
            .padding(.bottom, theme.spacing.s12)
            SkeletonBox(width: 200, height: 13)
            SkeletonBox(height: 11)
            SkeletonBox(height: 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TranslationBanner: View {
    @Environment(\.appTheme) private var theme
    let text: String
    let hue: Color

    var body: some View {
        Text(text).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s10).frame(maxWidth: .infinity, alignment: .leading)
            .background(hue.opacity(0.11), in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(hue.opacity(0.38), lineWidth: theme.borders.hairline))
            .padding(.bottom, theme.spacing.s16)
    }
}

/// The translated title and its body, laid out as the Original tab lays the source out: under the same heading ("Repro
/// steps" for a bug) and through the same renderer. A ZenTao body is HTML and comes back from the translator as HTML, so it
/// is drawn as HTML (lists, bold, images) - shown as Markdown its tags were printed as text.
private struct TranslatedRecord: View {
    @Environment(\.appTheme) private var theme
    let record: TranslationRecord
    let ticket: Ticket
    let images: BodyImageHooks

    var body: some View {
        let isBug: Bool = { if case .zentaoBug? = ticket.providerEntity { true } else { false } }()
        VStack(alignment: .leading, spacing: 0) {
            Text(record.translatedTitle).font(theme.typography.title).foregroundStyle(theme.colors.tx).lineSpacing(theme.spacing.s4).textSelection(.enabled)
            DetailSectionTitle(isBug ? appString("fieldSteps", "Repro steps") : appString("description", "Description"))
                .padding(.top, theme.spacing.s16)
            RichBodyText(record.translatedBody, html: isHtmlBody(ticket.providerType, record.translatedBody), fontSize: 15, height: 1.6, images: images)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
