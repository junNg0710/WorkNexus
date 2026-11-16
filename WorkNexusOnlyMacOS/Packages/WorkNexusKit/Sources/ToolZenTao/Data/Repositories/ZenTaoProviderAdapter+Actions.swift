import CoreDomain
import Foundation

/// Write actions of `ZenTaoProviderAdapter` through ZenTao's classic web actions (this ZenTao build has no
/// `/bugs/{id}/<action>` REST endpoints - they 404). Ported from zentao_adapter.dart.
extension ZenTaoProviderAdapter {
    public func assignTicket(_ ticket: Ticket, assignee: String, comment: String?, left: Double?) async -> Outcome<Bool> {
        await zenGuard {
            // Classic web action `{type}-assignTo-{id}`; mirrors the web client's assign request.
            let type = zenTaoType(of: ticket)
            let task: ZenTaoTaskEntity? = { if case .zentaoTask(let t) = ticket.providerEntity { return t } else { return nil } }()
            // A task's assign form also carries its hours left (required while the task is unfinished), which
            // ZenTao 20+ resets to 0 when the field is missing: the hours typed in, else the ones it already has.
            let hours: Double? = task.map { left ?? $0.left } ?? nil
            // `task::assignTo` takes the execution BEFORE the task id; with the id alone ZenTao reads it as the
            // execution and answers task 0's HTML page. The execution only picks the form's member list, so `0` is fine.
            let target = type == .task ? "\(task?.execution ?? "0")-\(ticket.externalKey)" : ticket.externalKey
            var form = ZenTaoForm()
            form.put("assignedTo", assignee)
            form.put("left", hours.map(zentaoHours))
            if let c = comment, !c.trimmingCharacters(in: .whitespaces).isEmpty { form.put("comment", c) }
            let resp = try await client.classicActionPost("\(type.pathSegment)-assignTo-\(target)", form)
            try ensureZenTaoActionOk(resp, "assign")
            return true
        }
    }

    public func resolveBug(_ ticket: Ticket, resolution: String, resolvedBuild: String?, assignee: String?, comment: String?) async -> Outcome<Bool> {
        await zenGuard {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            var form = ZenTaoForm()
            form.put("resolution", resolution)
            form.put("resolvedBuild", Self.nonBlank(resolvedBuild) ?? "trunk")
            form.put("resolvedDate", f.string(from: Date()))
            if let a = assignee, !a.isEmpty { form.put("assignedTo", a) }
            if let c = comment, !c.trimmingCharacters(in: .whitespaces).isEmpty { form.put("comment", c) }
            try ensureZenTaoActionOk(try await client.classicActionPost("bug-resolve-\(ticket.externalKey)", form), "resolve")
            return true
        }
    }

    public func activateBug(_ ticket: Ticket, openedBuild: String?, assignee: String?, comment: String?) async -> Outcome<Bool> {
        await zenGuard {
            // ZenTao's activate wants `openedBuild` as a non-empty STRING (like resolve's `resolvedBuild`), NOT an array.
            // Reopen assigns to the acting user (me) by default; otherwise ZenTao leaves the bug on whoever it was
            // parked on (the reporter, at resolve).
            let target = Self.nonBlank(assignee) ?? client.account
            var form = ZenTaoForm()
            form.put("openedBuild", Self.nonBlank(openedBuild) ?? "trunk")
            if !target.isEmpty { form.put("assignedTo", target) }
            if let c = comment, !c.trimmingCharacters(in: .whitespaces).isEmpty { form.put("comment", c) }
            try ensureZenTaoActionOk(try await client.classicActionPost("bug-activate-\(ticket.externalKey)", form), "activate")
            return true
        }
    }

    public func confirmBug(_ ticket: Ticket, assignee: String?, comment: String?) async -> Outcome<Bool> {
        await zenGuard {
            // No REST v1 bug actions on these builds (they 404): confirm goes through the classic web action.
            // Keep the bug on the acting user by default so it stays on their board.
            let target = Self.nonBlank(assignee) ?? client.account
            try await ZenTaoWorkflow(client: client).confirmBug(ticket.externalKey, assignee: target, comment: comment)
            return true
        }
    }

    private static func nonBlank(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }
}
