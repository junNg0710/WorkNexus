import CoreDomain
import CoreUI
import SwiftUI

/// The in-conversation search bar under the header: type to search, Enter / Shift+Enter (or the arrows) to step through the
/// matches and jump to them in the list, a time-range menu, and the history download under it.
/// Ported from: lib/features/chat/presentation/widgets/chat_thread_search_bar.dart
struct ChatThreadSearchBar: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let session: ChatThreadSession
    @FocusState private var focused: Bool

    var body: some View {
        let search = session.search
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s6) {
                Image(systemName: "magnifyingglass").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx2)
                TextField(shellString("chatSearchMessages", "Search in conversation…"),
                          text: Binding(get: { search.query }, set: { search.setQuery($0) }))
                    .textFieldStyle(.plain).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).focused($focused)
                    .onKeyPress(keys: [.return]) { press in stepFromKey(press.modifiers.contains(.shift) ? -1 : 1); return .handled }
                    .onKeyPress(.escape) { session.toggleSearch(); return .handled }
                ChatSearchPeriodButton(model: model, session: session)
                if !search.query.isEmpty { Status(search: search) }
                if !search.query.isEmpty {
                    AppIconButton("chevron.up", help: shellString("chatPrevious", "Previous")) { Task { await search.step(-1) } }
                        .disabled(search.matches.isEmpty)
                    AppIconButton("chevron.down", help: shellString("chatNext", "Next")) { Task { await search.step(1) } }
                        .disabled(search.matches.isEmpty)
                }
                AppIconButton("xmark", help: shellString("chatCancel", "Cancel")) { session.toggleSearch() }
            }
            .padding(.horizontal, theme.spacing.s8)
            .frame(height: theme.sizes.control36 + theme.spacing.s8)
            .background(theme.colors.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
            ChatHistoryDownloadPrompt(session: session)
        }
        .onAppear { focused = true }
    }

    private func stepFromKey(_ delta: Int) { Task { await session.search.step(delta) } }
}

/// Where the search stands: a spinner, "3 of 12", "3 of 100+", "No results" or the failure.
/// Ported from: lib/features/chat/presentation/widgets/chat_search_status.dart
private struct Status: View {
    @Environment(\.appTheme) private var theme
    let search: ChatThreadSearch

    var body: some View {
        if search.failed {
            Text(shellString("chatSearchFailed", "Couldn't search messages")).font(theme.typography.meta).foregroundStyle(theme.colors.red)
        } else if search.isLoading && search.matches.isEmpty {
            ProgressView().controlSize(.mini)
        } else {
            let count = search.matches.count
            Text(label(count)).font(theme.typography.caption).foregroundStyle(count == 0 ? theme.colors.tx3 : theme.colors.accent)
                .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
                .background(count == 0 ? theme.colors.panel2 : theme.colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: theme.radii.sm))
        }
    }

    private func label(_ count: Int) -> String {
        guard count > 0 else { return shellString("chatSearchNoMatches", "No results") }
        let current = min(max(search.activeIndex, 0), count - 1) + 1
        return shellString(search.hasMore ? "chatSearchMatchesMore" : "chatSearchMatches", search.hasMore ? "{current} of {total}+" : "{current} of {total}",
                           ["current": "\(current)", "total": "\(count)"])
    }
}

/// The search's time range — "Any time", "Past 7 days", … — as a small menu button; shared by every search of the account.
/// Ported from: lib/features/chat/presentation/widgets/chat_search_period_button.dart
private struct ChatSearchPeriodButton: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let session: ChatThreadSession

    var body: some View {
        Menu {
            ForEach(ChatSearchPeriod.allCases, id: \.self) { p in
                Button { pick(p) } label: {
                    Label(ChatShellLabels.searchPeriodLabel(p), systemImage: p == model.searchPeriod ? "checkmark" : p == .all ? "infinity" : "calendar")
                }
            }
        } label: {
            Label(ChatShellLabels.searchPeriodLabel(model.searchPeriod), systemImage: "calendar.badge.clock")
                .font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(shellString("chatSearchPeriod", "Time range"))
    }

    private func pick(_ p: ChatSearchPeriod) {
        guard p != model.searchPeriod else { return }
        model.searchPeriod = p
        session.history.reset()
        session.search.reload()
    }
}

/// Below the search: while the chat is searched and its stored history does not yet go back as far as the period, this
/// downloads the rest — at once — and shows its progress until it is done, stopped or failed.
/// Ported from: lib/features/chat/presentation/widgets/chat_history_download_prompt.dart
struct ChatHistoryDownloadPrompt: View {
    @Environment(\.appTheme) private var theme
    let session: ChatThreadSession

    private struct Trigger: Hashable { var searching: Bool; var idle: Bool }

    var body: some View {
        let history = session.history
        let searching = !session.search.query.trimmingCharacters(in: .whitespaces).isEmpty
        Group {
            switch history.phase {
            case .running(let p): HistoryProgress(progress: p) { history.cancel() }
            case .cancelled where searching:
                Stopped(message: shellString("chatHistoryDownloadStopped", "Stopped loading older messages"),
                        action: shellString("chatHistoryDownloadResume", "Resume"), isError: false) { history.start() }
            case .failed:
                Stopped(message: shellString("chatHistoryDownloadFailed", "Couldn't download older messages"),
                        action: shellString("retry", "Retry"), isError: true) { history.start() }
            default: EmptyView()
            }
        }
        .task(id: Trigger(searching: searching, idle: history.phase == .idle)) { await history.ensure(searching: searching) }
    }
}

private struct HistoryProgress: View {
    @Environment(\.appTheme) private var theme
    let progress: ChatHistoryProgress?
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            VStack(alignment: .leading, spacing: theme.spacing.s4) {
                HStack {
                    Text(shellString("chatHistoryDownloading", "Downloading older messages…"))
                    Spacer(minLength: 0)
                    if let progress {
                        Text(progress.total > 0
                             ? shellString("chatHistoryDownloadProgress", "{stored} of {total}", ["stored": "\(progress.stored)", "total": "\(progress.total)"])
                             : shellString("chatHistoryDownloadedCount", "Loaded {count} older messages…", ["count": "\(progress.stored)"]))
                    }
                }
                .font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                if let fraction = progress?.fraction { ProgressView(value: fraction).tint(theme.colors.accent) }
                else { ProgressView().progressViewStyle(.linear).tint(theme.colors.accent) }
            }
            AppIconButton("xmark", help: shellString("chatHistoryDownloadStop", "Stop loading older messages"), action: onStop)
        }
        .padding(theme.spacing.s6).background(theme.colors.panel2)
    }
}

private struct Stopped: View {
    @Environment(\.appTheme) private var theme
    let message: String, action: String, isError: Bool, onAction: () -> Void

    var body: some View {
        HStack {
            Text(message).font(theme.typography.meta).foregroundStyle(isError ? theme.colors.red : theme.colors.tx2)
            Spacer(minLength: 0)
            AppButton(action, kind: .ghost, action: onAction)
        }
        .padding(theme.spacing.s6).background(theme.colors.panel2)
    }
}
