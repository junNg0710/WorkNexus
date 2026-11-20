/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Hands every picked ticket to one person, with an optional note on each. The people are those of the picked tickets'
/// teams (executions / products, which a cross-execution view like Only me mixes), with their load on the board; a
/// ticket whose team the person is not on is skipped, and said so before anything is sent.
struct ZentaoBulkAssignDialog: View {
    @Environment(\.toasts) private var toasts
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let bugs: Bool; let model: ZentaoBulkModel; let onClose: () -> Void
    @State private var source: ZentaoLoad<ZentaoBulkAssignSource> = .loading
    @State private var login: String?
    @State private var filter = ""
    @State private var note: ZentaoNoteModel?
    /// Hours left for the picked tasks that have none: ZenTao will not assign an unfinished task without them.
    @State private var left = ""

    init(deps: ZentaoDependencies, state: ZentaoUIState, bugs: Bool, model: ZentaoBulkModel, initialLogin: String? = nil,
         onClose: @escaping () -> Void) {
        self.deps = deps; self.state = state; self.bugs = bugs; self.model = model; self.onClose = onClose
        _login = State(initialValue: initialLogin)
    }

    /// The hours typed in, when they are a valid amount.
    private var hours: Double? {
        let h = zentaoParseHours(left)
        return CheckZenTaoAssignLeft()(h) == nil ? h : nil
    }

    private func plan(_ targets: [Ticket]) -> ZenTaoBulkPlan {
        guard let login else { return ZenTaoBulkPlan(tickets: [], skipped: []) }
        let teams = source.value.map { ZenTaoAssignTeams(members: $0.teams.mapValues { Set($0.map(\.account)) }) }
        return PlanBulkAction()(targets, .assign(login: login, comment: nil, left: hours), canTake: teams.map { t in { t.canTake($0, $1) } })
    }

    private func people(_ targets: [Ticket], _ s: ZentaoBulkAssignSource) -> [ZenTaoBulkAssignee] {
        let all = ListBulkAssignees()(tickets: targets, teams: s.teams, fallback: s.fallback,
                                      workload: state.workload(bugs: bugs), pinned: state.pinnedPeople)
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.login.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let targets = state.bulkTargets(bugs: bugs)
        let plan = plan(targets)
        ZentaoActionFrame(title: appFormat("leaderBulkAssignTitle", "Assign %1$@ tickets", "\(targets.count)"), icon: "person.badge.plus",
                          submitLabel: appFormat("leaderBulkApply", "Apply to %1$@", "\(plan.tickets.count)"), busy: false,
                          canSubmit: !plan.isEmpty, onSubmit: {
                              guard let login else { return }
                              let comment = note?.value
                              onClose()
                              Task { await model.run(.assign(login: login, comment: comment, left: hours), plan: plan, state: state, bugs: bugs, toasts: toasts) }
                          }, onClose: onClose) {
            ZentaoFieldLabel(appString("fieldAssignTo", "Assign to"))
            switch source {
            case .loading: AppInlineSpinner()
            case .failed: AppInlineNote(appString("taskDetailUsersLoadFailed", "Couldn't load users"), isError: true)
            case .loaded(let s):
                AppSearchField(text: $filter, hint: appString("searchUsers", "Search users…"))
                Color.clear.frame(height: theme.spacing.s8)
                ZentaoBulkAssigneeList(accountId: targets.first?.accountId ?? "", people: people(targets, s), picked: login,
                                       ticketCount: targets.count) { login = $0 }
            }
            ZentaoFieldGap()
            let needing = targets.filter { NeedsHoursLeft()($0) }.count
            if needing > 0 {
                ZentaoTaskHoursField(label: appFormat("leaderBulkHoursLeft", "Hours left, for the %1$@ tasks that have none", "\(needing)"),
                                     text: $left)
                if !left.trimmingCharacters(in: .whitespaces).isEmpty, let problem = CheckZenTaoAssignLeft()(zentaoParseHours(left)) {
                    ZentaoTaskProblemLine(problem)
                }
                ZentaoFieldGap()
            }
            if let first = targets.first, let note {
                ZentaoFieldLabel(appString("zentaoNote", "Note"))
                ZentaoNoteField(deps: deps, ticket: first, note: note)
                ZentaoFieldGap()
            }
            if login != nil { ZentaoBulkSummary(plan: plan) }
        }
        .task {
            let targets = state.bulkTargets(bugs: bugs)
            if note == nil, let first = targets.first { note = ZentaoNoteModel(ticket: first) }
            switch await state.bulkAssignSource(targets) {
            case .success(let s): source = .loaded(s)
            case .failure(let f): source = .failed(f)
            }
        }
    }
}
