/// Ported from: lib/tools/zentao/presentation/detail/task_bugs_card.dart, providers/task_bugs_providers.dart
import CoreDomain
import CoreUI
import Observation
import SharedKit
import SwiftUI

/// The bugs related to one ZenTao task: read from the local database (`ListTaskBugs`) as it changes, while the task's
/// execution's bugs are fetched into it once (a recent read of them may already hold them).
@MainActor @Observable
final class ZentaoTaskBugsModel {
    private(set) var bugs: [Ticket] = []
    private(set) var syncing = false
    private(set) var failed = false
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var sync: Task<Void, Never>?

    func start(_ deps: ZentaoDependencies, ticket: Ticket) {
        watch?.cancel()
        let stream = deps.services.tickets.watchTickets()
        watch = Task { [weak self] in
            for await all in stream { self?.bugs = ListTaskBugs()(task: ticket, tickets: all) }
        }
        retry(deps, ticket: ticket)
    }

    func retry(_ deps: ZentaoDependencies, ticket: Ticket) {
        sync?.cancel()
        guard case .zentaoTask(let t) = ticket.providerEntity, let execution = t.execution else { return }
        syncing = true; failed = false
        sync = Task { [weak self] in
            let r = await deps.taskBugs.syncTaskBugs(accountId: ticket.accountId, executionId: execution, taskId: ticket.externalKey)
            guard !Task.isCancelled else { return }
            self?.syncing = false
            if case .failure = r { self?.failed = true }
        }
    }

    func stop() { watch?.cancel(); sync?.cancel() }
}

/// A ZenTao task's related bugs as a sidebar card; tapping one opens it. Nothing shows while there are none, unless
/// the fetch failed: then it says so, with a retry. The owner starts `model` (an empty card has no view of its own
/// to start it from).
struct ZentaoTaskBugsCard: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let ticket: Ticket; let model: ZentaoTaskBugsModel

    var body: some View {
        Group {
            if !model.bugs.isEmpty || model.failed {
                DetailRegionCard(padding: theme.spacing.s12) {
                    VStack(alignment: .leading, spacing: theme.spacing.s4) {
                        HStack(spacing: theme.spacing.s6) {
                            SectionLabel("\(appString("relatedBugs", "Related bugs")) (\(model.bugs.count))")
                            if model.syncing { ProgressView().controlSize(.mini) }
                        }
                        ForEach(model.bugs) { bug in ZentaoRelatedBugRow(bug: bug) { deps.nav.openTicket(bug.id) } }
                        if model.failed { ZentaoLoadFailedLine { model.retry(deps, ticket: ticket) } }
                    }
                }
            }
        }
    }
}

/// One related bug: its id and title (up to two lines), then its status.
private struct ZentaoRelatedBugRow: View {
    @Environment(\.appTheme) private var theme
    let bug: Ticket; let onTap: () -> Void
    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onTap, cornerRadius: theme.radii.sm) {
            HStack(alignment: .top, spacing: theme.spacing.s10) {
                Text("#\(bug.externalKey)").font(theme.typography.mono).foregroundStyle(c.tx2)
                Text(bug.title).font(theme.typography.meta).foregroundStyle(c.accent).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                TintedPill(statusLabel(bug.status), tint: c.statusColor(bug.status))
            }
            .padding(.vertical, theme.spacing.s6)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
    }
}

/// The fetch failed: says so, with a retry link.
private struct ZentaoLoadFailedLine: View {
    @Environment(\.appTheme) private var theme
    let onRetry: () -> Void
    var body: some View {
        HStack(spacing: theme.spacing.s6) {
            Text(appString("relatedBugsLoadFailed", "Couldn't load the related bugs from ZenTao.")).font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
            Button(appString("retry", "Retry"), action: onRetry).buttonStyle(.plain).font(theme.typography.caption).foregroundStyle(theme.colors.accent)
        }
        .padding(.vertical, theme.spacing.s6)
    }
}
