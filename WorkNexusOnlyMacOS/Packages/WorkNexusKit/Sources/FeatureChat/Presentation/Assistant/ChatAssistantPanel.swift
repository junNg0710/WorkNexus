/// Ported from: lib/features/chat/presentation/widgets/chat_assistant_panel.dart
import CoreUI
import SwiftUI

/// The panel beside a chat where the AI summarizes it: pick which messages and the language, then read the overview, key
/// points, decisions, action items and open questions.
struct ChatAssistantPanel: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.chatSettings) private var settings
    let session: ChatThreadSession

    private var assistant: ChatAssistantModel { session.assistant }

    var body: some View {
        let summary = assistant.summary
        ChatSidePanelFrame(title: appString("chatAiAssistant", "AI assistant"), onClose: { session.state.closePanel() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.s8) {
                    Text(appString("chatAiSummaryIntro",
                                   "Get the gist of the conversation: key points, decisions, who does what and what is still open."))
                        .font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2).fixedSize(horizontal: false, vertical: true)
                    Text(appString("chatAiScopeLabel", "Messages to summarize")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                        .padding(.top, theme.spacing.s12)
                    ScopePicker(assistant: assistant)
                    if let services, !services.aiLanguages.isEmpty {
                        LanguageRow(assistant: assistant, languages: services.aiLanguages) { summarize() }
                    }
                    HStack(spacing: theme.spacing.s8) {
                        AppButton(summary.summary == nil ? appString("chatAiSummarize", "Summarize") : appString("chatAiRegenerate", "Summarize again"),
                                  systemImage: "sparkles", kind: .primary) { summarize() }
                            .disabled(summary.isLoading)
                        if summary.isLoading {
                            AppButton(appString("cancel", "Cancel"), kind: .ghost) { summary.cancel() }
                        }
                    }
                    .padding(.vertical, theme.spacing.s8)
                    PhaseView(phase: summary.phase)
                }
                .padding(theme.spacing.s20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func summarize() {
        guard let services else { return }
        let context = ChatAiContext(services: services, settings: settings, state: session.state)
        let assistant = assistant, scope = assistant.scope
        Task { await assistant.summarize(scope, context: context) }
    }
}

/// Unread / latest 50 / 100 / 200.
private struct ScopePicker: View {
    let assistant: ChatAssistantModel

    var body: some View {
        let scope = assistant.scope, unread = assistant.unreadOnOpen
        var tabs: [AppSegmentedTab] = []
        if unread > 0 {
            tabs.append(AppSegmentedTab(label: appString("chatAiScopeUnread", "Unread"), active: scope.unread, count: unread) {
                assistant.scope = ChatSummaryScope(unread: true, count: unread)
            })
        }
        for count in ChatSummaryScope.latestCounts {
            tabs.append(AppSegmentedTab(label: "\(count)", active: !scope.unread && scope.count == count) {
                assistant.scope = ChatSummaryScope(unread: false, count: count)
            })
        }
        return AppSegmentedTabs(tabs)
    }
}

/// "Summary language" and its picker. A summary on screen is written again in the new language; before one, the pick waits
/// for Summarize.
private struct LanguageRow: View {
    @Environment(\.appTheme) private var theme
    let assistant: ChatAssistantModel
    let languages: [ChatAiLanguage]
    let resummarize: () -> Void

    var body: some View {
        let selected = assistant.language(languages)
        HStack {
            Text(appString("chatAiSummaryLanguage", "Summary language")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
            Spacer(minLength: theme.spacing.s8)
            Menu {
                ForEach(languages, id: \.code) { lang in
                    Button { pick(lang.code) } label: {
                        Label("\(lang.flag)  \(lang.nativeName)", systemImage: lang.code == selected.code ? "checkmark" : "")
                    }
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
            .help(appString("chatAiSummaryLanguage", "Summary language"))
        }
    }

    private func pick(_ code: String) {
        ChatAiPreferences.shared.summaryLanguage = code
        if assistant.summary.summary != nil && !assistant.summary.isLoading { resummarize() }
    }
}

/// The summary, what shows while the model writes, or why it failed.
private struct PhaseView: View {
    @Environment(\.appTheme) private var theme
    let phase: ChatAiPhase<ChatSummary>

    var body: some View {
        switch phase {
        case .idle: EmptyView()
        case .loading:
            HStack(spacing: theme.spacing.s12) {
                ProgressView().controlSize(.small)
                Text(appString("chatAiSummarizing", "Summarizing…")).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
            }
        case .failed(let reason): AppInlineNote(ChatComposerController.aiFailed(reason), isError: true)
        case .ready(let summary): ChatSummaryView(summary: summary)
        }
    }
}
