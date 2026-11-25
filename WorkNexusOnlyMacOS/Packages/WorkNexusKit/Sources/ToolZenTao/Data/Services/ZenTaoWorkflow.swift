import CoreDomain
import Foundation

// Ported from: lib/tools/zentao/data/models/{zentao_action_result,zentao_workflow}.dart

/// Throws unless ZenTao processed classic action `action` (`bug-resolve`, `task-start`...).
///
/// Unlike the REST channel, a POST that ZenTao did NOT process comes back as the action page's HTML (a String)
/// or a login redirect rather than a `{result: 'success'}` JSON object - so anything that isn't a non-failing
/// JSON object is a failure. ZenTao 18.x wraps every `.json` reply as `{status: 'success', data: '<json>'}` - a
/// refused action too, with its `{result: 'fail', message}` inside - so the unwrapped reply is checked.
func ensureZenTaoActionOk(_ resp: ZenTaoResponse, _ action: String) throws {
    let code = resp.status
    let reply = classicPayload(resp.data)
    if code < 400, let reply, !actionRefused(reply) { return }
    let detail = reply == nil
        ? "ZenTao did not process the action (auth/permission, CSRF, or the action does not exist)"
        : flattenMessages(isNull(reply!["message"]) ? reply!["error"] : reply!["message"]).joined(separator: " ")
    throw ZenTaoError.http(status: code, message: "ZenTao \(action) failed (HTTP \(code))\(detail.isEmpty ? "" : ": \(detail)")",
                           hasResponse: true)
}

private func actionRefused(_ reply: JSON) -> Bool {
    str(reply["result"]) == "fail"
        || ["fail", "failed"].contains(str(reply["status"]) ?? "")
        // 18.x answers a signed-out request by sending the client to log in.
        || (str(reply["locate"])?.contains("user-login") ?? false)
}

/// ZenTao's reason: a string, or field errors as a map or list (`{left: ['must be more than 0']}`).
private func flattenMessages(_ raw: Any?) -> [String] {
    if isNull(raw) { return [] }
    if let entries = asEntries(raw) { return entries.flatMap { flattenMessages($0.value) } }
    if let list = raw as? [Any] { return list.flatMap { flattenMessages($0) } }
    let text = (str(raw) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? [] : [text]
}

/// Hours as ZenTao's forms take them: `2`, `2.5`.
func zentaoHours(_ hours: Double) -> String {
    let rounded = (hours * 100).rounded() / 100
    return rounded == rounded.rounded() ? "\(Int(rounded))" : "\(rounded)"
}

/// A date-time as ZenTao's forms take it (server-local `yyyy-MM-dd HH:mm:ss`).
func zentaoDateTime(_ time: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.string(from: time)
}

private func nonEmpty(_ value: String?) -> String? {
    let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? nil : text
}

/// ZenTao's bug and task status actions, through its classic web actions (`bug-close-{id}`, `task-start-{id}`...)
/// with the fields its own forms send. Only a form's own fields are sent: ZenTao 18.x writes every posted field
/// to the task row, so an unknown one fails the save.
struct ZenTaoWorkflow {
    let client: ZenTaoClient
    var now: () -> Date = Date.init

    /// Closes resolved bug `bugId`.
    func closeBug(_ bugId: String, comment: String? = nil) async throws {
        var form = ZenTaoForm()
        form.put("comment", nonEmpty(comment))
        try ensureZenTaoActionOk(try await client.classicActionPost("bug-close-\(bugId)", form), "close")
    }

    /// Confirms bug `bugId` (ZenTao sets `confirmed = 1`), assigning it to `assignee`.
    ///
    /// ZenTao 20+ names the action `bug-confirm`, 18.x `bug-confirmBug`; the form page tells which one this
    /// server has. 20+ also writes every form field left out of the POST with its default (priority 3, empty
    /// status, type, deadline and CC list - an empty status is refused), so the bug's own values go along, as
    /// ZenTao's form sends them.
    func confirmBug(_ bugId: String, assignee: String, comment: String? = nil) async throws {
        func form(_ action: String) async throws -> JSON? {
            asMap(classicPayload(try await client.classicGet(action).data)?["bug"])
        }
        var action = "bug-confirm-\(bugId)"
        var bug = try await form(action)
        if bug == nil {
            action = "bug-confirmBug-\(bugId)"
            bug = try await form(action) ?? [:]
        }
        let b = bug ?? [:]
        let deadline = zentaoDate(b["deadline"])
        let type = zentaoText(b["type"]).trimmingCharacters(in: .whitespaces)
        let status = zentaoText(b["status"]).trimmingCharacters(in: .whitespaces)
        var f = ZenTaoForm()
        f.put("uid", client.formUid())
        f.put("assignedTo", assignee)
        f.put("pri", "\(zentaoIntOr(b["pri"], 3))")
        // Only an active bug can be confirmed.
        f.put("status", status.isEmpty ? "active" : status)
        if !type.isEmpty { f.put("type", type) }
        if !deadline.isEmpty { f.put("deadline", deadline) }
        f.put("mailto[]", list: zentaoCsv(b["mailto"]))
        f.put("comment", nonEmpty(comment))
        try ensureZenTaoActionOk(try await client.classicPost(action, .form(f)), "confirm")
    }

    /// Deletes bug or task `id` (`kind`: "bug" or "task"). ZenTao keeps it in its recycle bin.
    func delete(kind: String, id: String) async throws {
        try await client.deleteV1("/\(kind == "bug" ? "bugs" : "tasks")/\(id)")
    }

    /// Runs `action` on `task` with `input`.
    func runTaskAction(_ task: Ticket, _ action: ZenTaoTaskAction, _ input: ZenTaoTaskActionInput) async throws {
        var fields = ZenTaoForm()
        fields.put("uid", client.formUid())
        fields.merge(taskForm(task, action, input))
        let files = action.asksFiles ? input.files : []
        let body: ZenTaoBody = files.isEmpty
            ? .form(fields)
            : .multipart(fields: { var f = fields; f.put("labels[]", list: files.map(\.name)); return f }(),
                         files: files.map { ("files[]", $0) })
        try ensureZenTaoActionOk(try await client.classicPost("task-\(action.name)-\(task.externalKey)", body), action.name)
    }

    private func taskForm(_ task: Ticket, _ action: ZenTaoTaskAction, _ input: ZenTaoTaskActionInput) -> ZenTaoForm {
        var logged = 0.0
        var started: Date?
        if case .zentaoTask(let t) = task.providerEntity { logged = t.consumed ?? 0; started = t.realStarted }
        let now = self.now()
        let began = input.began ?? started ?? now
        let comment = nonEmpty(input.comment)
        let chosen = nonEmpty(input.assignee)
        var f = ZenTaoForm()
        switch action {
        case .start, .restart:
            // ZenTao takes the new total logged, not this session's hours.
            f.put("consumed", zentaoHours(logged + input.spent))
            f.put("left", zentaoHours(input.left))
            f.put("realStarted", zentaoDateTime(began))
            // ZenTao 20+ clears the assignee when the field is missing.
            f.put("assignedTo", chosen ?? nonEmpty(task.assignee) ?? client.account)
            f.put("comment", comment)
        case .finish:
            f.put("currentConsumed", zentaoHours(input.spent))
            // 18.x reads the new total; 20+ adds currentConsumed itself.
            f.put("consumed", zentaoHours(logged + input.spent))
            f.put("realStarted", zentaoDateTime(began))
            // ZenTao refuses a finish dated before the start.
            f.put("finishedDate", zentaoDateTime(input.ended ?? (began > now ? began : now)))
            // Left out, ZenTao hands a finished task back to its creator.
            f.put("assignedTo", chosen)
            f.put("comment", comment)
        case .activate:
            f.put("left", zentaoHours(input.left))
            f.put("assignedTo", chosen ?? client.account)
            f.put("comment", comment)
        case .pause, .close, .cancel:
            f.put("comment", comment)
        }
        return f
    }
}
