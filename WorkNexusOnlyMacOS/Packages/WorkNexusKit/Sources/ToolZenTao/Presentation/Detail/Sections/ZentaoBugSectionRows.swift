/// Ported from: lib/tools/zentao/presentation/detail/bug_detail_sections.dart (the row lists)
import CoreDomain
import CoreUI
import Foundation

/// The rows of a ZenTao bug's two sidebar cards: what the bug *is* (classification) and how it *moved* (lifecycle).
struct ZentaoBugSectionRows {
    typealias Row = (String, String)
    var filled: [Row] = []
    var empty: [Row] = []
    var lifecycle: [Row] = []

    init(bug: ZenTaoBugEntity, ticket: Ticket, dateFormat: String) {
        let active = ticket.providerStatus.trimmingCharacters(in: .whitespaces).lowercased() == "active"
        let reopened = bug.activatedCount ?? 0
        func severity(_ s: Int?) -> String { zentaoSeverityLabel(s).map { "S\(s!) · \($0)" } ?? "" }
        // Grouped by what a reader looks for: the triage facts first, then where the bug lives, then what it links to.
        // The id-only fields fall to the empty group when unset (ZenTao reports them as "0").
        var classification: [Row] = [
            (appString("status", "Status"), ticket.providerStatus),
            (appString("fieldSeverity", "Severity"), severity(bug.severity)),
            (appString("priority", "Priority"), hasExplicitPriority(ticket) ? priorityLabel(ticket.providerType, ticket.priority) : ""),
        ]
        // Whether an open bug was confirmed matters for triage; once resolved the flag is history.
        if active {
            classification.append((appString("fieldConfirmation", "Confirmation"),
                                   bug.confirmed == 1 ? appString("confirmed", "Confirmed") : appString("bugUnconfirmed", "Not confirmed")))
        }
        if reopened > 0 { classification.append((appString("fieldReopened", "Reopened"), "\(reopened)")) }
        classification += [
            (appString("fieldType", "Type"), zentaoBugTypeLabel(bug.bugType) ?? ""),
            (appString("fieldProduct", "Product"), zentaoNameOr(bug.productName, bug.product)),
            (appString("fieldExecution", "Execution"), zentaoNameOr(bug.executionName, bug.execution)),
            (appString("fieldModule", "Module"), bug.module ?? ""),
            (appString("fieldBranch", "Branch"), bug.branch ?? ""),
            (appString("fieldPlan", "Plan"), zentaoNameOr(bug.planName, bug.plan)),
            (appString("fieldOpenedBuild", "Opened build"), bug.openedBuild ?? ""),
            (appString("fieldStory", "Story"), zentaoJoined([bug.storyTitle, bug.story])),
            (appString("task", "Task"), zentaoJoined([bug.taskName, bug.task])),
        ]
        filled = classification.filter { !zentaoIsEmptyValue($0.1) }
        empty = classification.filter { zentaoIsEmptyValue($0.1) }.map { ($0.0, "—") }
        func when(_ d: Date?) -> String { formatWhen(d, format: dateFormat) }
        lifecycle = [
            (appString("fieldOpened", "Opened"), when(bug.openedDate)),
            (appString("fieldAssigned", "Assigned"), when(bug.assignedDate)),
            (appString("fieldResolvedBy", "Resolved by"), bug.resolvedBy ?? ""),
            (appString("fieldResolved", "Resolved"), when(bug.resolvedDate)),
            (appString("fieldClosedBy", "Closed by"), bug.closedBy ?? ""),
            (appString("fieldClosed", "Closed"), when(bug.closedDate)),
            (appString("lastEdited", "Last edited"), when(bug.lastEditedDate)),
        ].filter { !zentaoIsEmptyValue($0.1) }
    }
}

/// The rows of a ZenTao task's sidebar cards (classification, effort, lifecycle); rows without a value are left out.
struct ZentaoTaskSectionRows {
    typealias Row = (String, String)
    var classification: [Row] = []
    var effort: [Row] = []
    var lifecycle: [Row] = []

    init(task: ZenTaoTaskEntity, ticket: Ticket, parentName: String?, dateFormat: String) {
        func when(_ d: Date?) -> String { formatWhen(d, format: dateFormat) }
        func hours(_ h: Double?) -> String { appFormat("hoursValue", "%1$@ h", zentaoHoursText(h ?? 0)) }
        let summary = SummarizeTaskEffort()(task)
        // Like ZenTao's Basic Info: what the task is, how far along, then where it sits and what it comes from.
        var progress = ""
        if let s = summary {
            let f = NumberFormatter(); f.numberStyle = .percent; f.maximumFractionDigits = 0
            progress = f.string(from: NSNumber(value: s.progress)) ?? ""
        }
        classification = Self.filled([
            (appString("status", "Status"), ticket.providerStatus),
            (appString("priority", "Priority"), hasExplicitPriority(ticket) ? priorityLabel(ticket.providerType, ticket.priority) : ""),
            (appString("fieldType", "Type"), zentaoTaskTypeLabel(task.taskType) ?? ""),
            (appString("fieldProgress", "Progress"), progress),
            (appString("fieldExecution", "Execution"), task.executionName ?? task.execution ?? ""),
            (appString("parentTask", "Parent task"), task.parentId ?? ""),
            (appString("fieldStory", "Story"), task.story ?? ""),
            (appString("fieldFromBug", "From bug"), task.fromBug ?? ""),
        ])
        var e: [Row] = []
        if let s = summary {
            e += [(appString("estimate", "Estimate"), hours(s.estimate)), (appString("fieldLogged", "Logged"), hours(s.consumed)),
                  (appString("zentaoHoursLeft", "Hours left"), hours(s.left))]
        }
        e += [(appString("fieldEstStarted", "Start"), task.estStarted ?? ""), (appString("fieldActualStart", "Actual start"), when(task.realStarted)),
              (appString("fieldDeadline", "Deadline"), task.deadline ?? "")]
        effort = Self.filled(e)
        lifecycle = Self.filled([
            (appString("fieldOpenedBy", "Opened by"), task.openedBy ?? ""), (appString("fieldOpened", "Opened"), when(task.openedDate)),
            (appString("assignedTo", "Assigned to"), ticket.assignee ?? ""),
            (appString("fieldFinishedBy", "Finished by"), task.finishedBy ?? ""), (appString("fieldFinished", "Finished"), when(task.finishedDate)),
            (appString("fieldClosedBy", "Closed by"), task.closedBy ?? ""), (appString("fieldClosed", "Closed"), when(task.closedDate)),
            (appString("lastEdited", "Last edited"), when(task.lastEditedDate)),
        ])
    }

    /// The rows with a value: ZenTao reports unset ids as "0".
    static func filled(_ rows: [Row]) -> [Row] { rows.filter { !zentaoIsEmptyValue($0.1) } }
}
