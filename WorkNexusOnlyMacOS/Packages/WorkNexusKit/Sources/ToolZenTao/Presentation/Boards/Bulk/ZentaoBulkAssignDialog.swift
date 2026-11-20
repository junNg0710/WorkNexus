/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Hands every picked ticket to one person. The person picked stays in a box of its own above the search; the people are
/// those of the picked tickets' teams (executions / products, which a cross-execution view like Only me mixes), with their
/// load on the board. Every ticket has its own row: its hours left (tasks) and its own note, over a shared note and shared
/// hours for the tasks that have none. A ticket ZenTao would refuse is skipped, and said so before anything is sent.
struct ZentaoBulkAssignDialog: View {
    @Environment(\.toasts) private var toasts
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let bugs: Bool; let model: ZentaoBulkModel; let onClose: () -> Void
    @State private var source: ZentaoLoad<ZentaoBulkAssignSource> = .loading
    @State private var login: String?
    @State private var filter = ""
    @State private var form = ZentaoBulkAssignForm()

    init(deps: ZentaoDependencies, state: ZentaoUIState, bugs: Bool, model: ZentaoBulkModel, initialLogin: String? = nil,
         onClose: @escaping () -> Void) {
        self.deps = deps; self.state = state; self.bugs = bugs; self.model = model; self.onClose = onClose
        _login = State(initialValue: initialLogin)
    }

    private func action(_ login: String) -> ZenTaoBulkAction {
        .assign(login: login, comment: form.sharedNote, left: form.sharedHours, details: form.details)
    }

    private func plan(_ targets: [Ticket]) -> ZenTaoBulkPlan {
        guard let login else { return ZenTaoBulkPlan(tickets: [], skipped: []) }
        let teams = source.value.map { ZenTaoAssignTeams(members: $0.teams.mapValues { Set($0.map(\.account)) }) }
        return PlanBulkAction()(targets, action(login), canTake: teams.map { t in { t.canTake($0, $1) } })
    }

    private func people(_ targets: [Ticket], _ s: ZentaoBulkAssignSource) -> [ZenTaoBulkAssignee] {
        ListBulkAssignees()(tickets: targets, teams: s.teams, fallback: s.fallback, workload: state.workload(bugs: bugs), pinned: state.pinnedPeople)
    }

    var body: some View {
        let targets = state.bulkTargets(bugs: bugs)
        let plan = plan(targets)
        ZentaoActionFrame(title: appFormat("leaderBulkAssignTitle", "Assign %1$@ tickets", "\(targets.count)"), icon: "person.badge.plus",
                          submitLabel: appFormat("leaderBulkApply", "Apply to %1$@", "\(plan.tickets.count)"), busy: false,
                          canSubmit: !plan.isEmpty, onSubmit: {
                              guard let login else { return }
                              let action = action(login)
                              onClose()
                              Task { await model.run(action, plan: plan, state: state, bugs: bugs, toasts: toasts) }
                          }, onClose: onClose) {
            ZentaoFieldLabel(appString("fieldAssignTo", "Assign to"))
            switch source {
            case .loading: AppInlineSpinner()
            case .failed: AppInlineNote(appString("taskDetailUsersLoadFailed", "Couldn't load users"), isError: true)
            case .loaded(let s):
                ZentaoBulkAssigneePicker(accountId: targets.first?.accountId ?? "", people: people(targets, s), ticketCount: targets.count,
                                         picked: $login, filter: $filter)
            }
            ZentaoFieldGap()
            ZentaoBulkShared(form: form, tasksWithoutHours: targets.filter { NeedsHoursLeft()($0) }.count)
            ZentaoFieldGap()
            ZentaoBulkTicketRows(tickets: targets, plan: login == nil ? nil : plan, form: form)
            if login != nil {
                ZentaoFieldGap()
                ZentaoBulkSummary(plan: plan)
            }
        }
        .task {
            switch await state.bulkAssignSource(state.bulkTargets(bugs: bugs)) {
            case .success(let s): source = .loaded(s)
            case .failure(let f): source = .failed(f)
            }
        }
    }
}

/// Whether a ticket is a ZenTao task (only a task has hours left to give).
func zentaoIsTask(_ t: Ticket) -> Bool {
    if case .zentaoTask? = t.providerEntity { return true }
    return (t.externalType ?? "").lowercased() == "task"
}
