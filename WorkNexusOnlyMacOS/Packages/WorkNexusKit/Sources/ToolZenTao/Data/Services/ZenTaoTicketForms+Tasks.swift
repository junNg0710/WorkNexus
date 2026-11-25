import CoreDomain
import Foundation

// Ported from: lib/tools/zentao/data/models/zentao_task_forms.dart
/// ZenTao's task forms (`task-create` / `task-edit`, and the batch form for a new subtask).
extension ZenTaoTicketForms {
    /// A new task's form in execution `executionId` (`'0'`: ZenTao picks its current one); a subtask of task
    /// `parentId` when given; or a copy of task `copyOf` when given; or made from bug `fromBug` (ZenTao's "Convert to
    /// Task": the form starts from the bug, and saving it writes on the bug which task it became).
    func newTask(_ executionId: String, parentId: String? = nil, copyOf: String? = nil, fromBug: String? = nil) async throws -> TaskForm {
        let copySuffix = (copyOf?.isEmpty == false) ? "-\(copyOf!)" : ""
        let bug = fromBug?.isEmpty == false ? fromBug : nil
        let p = try await page(bug.map { taskFromBugPath(executionId, bug: $0) } ?? "task-create-\(executionId)-0-0\(copySuffix)")
        let legacy = p["moduleOptionMenu"] != nil
        let task = asMap(p["task"]) ?? [:]
        var options = taskOptions(page: p)
        // The create form may not list the parent (18.x lists no parents).
        if let parentId, !options.parents.contains(where: { $0.value == parentId }) {
            options.parents.insert(FormOption(value: parentId, label: "#\(parentId)"), at: 0)
        }
        var draft = TaskDraft(execution: executionId != "0" ? executionId : zentaoId(firstNonNull(idOf(p["execution"]), task["execution"])))
        draft.parent = parentId ?? "0"
        draft.module = zentaoId(task["module"])
        draft.story = zentaoId(task["story"])
        draft.name = zentaoText(task["name"])
        draft.type = orDefault(task["type"], "devel")
        draft.pri = zentaoIntOr(task["pri"], 3)
        draft.estimate = zentaoNumber(task["estimate"])
        draft.assignedTo = zentaoText(task["assignedTo"])
        draft.estStarted = zentaoDate(task["estStarted"])
        draft.deadline = zentaoDate(task["deadline"])
        draft.desc = str(task["desc"]) ?? ""
        draft.color = zentaoText(task["color"])
        draft.mailto = zentaoCsv(task["mailto"])
        draft.keywords = zentaoText(task["keywords"])
        var kept: [String: String] = legacy ? [zentaoLegacyKey: "1"] : [:]
        if let bug { kept[zentaoFromBugKey] = bug }
        return TaskForm(draft: draft, options: options, kept: kept)
    }

    /// `task-create` for a task made from `bug`: ZenTao reads the bug's id as the seventh argument of the page
    /// (`executionID, storyID, moduleID, taskID, todoID, extra, bugID`), in 18.x and 20+ alike.
    func taskFromBugPath(_ executionId: String, bug: String) -> String { "task-create-\(executionId)-0-0-0-0--\(bug)" }

    func editTask(_ taskId: String) async throws -> TaskForm {
        let p = try await page("task-edit-\(taskId)")
        let legacy = p["parentTask"] == nil
        guard let task = asMap(p["task"]) else { throw Failure.notFound("ZenTao task \(taskId) not found") }
        var draft = TaskDraft(id: taskId, execution: zentaoId(task["execution"]))
        draft.module = zentaoId(task["module"])
        draft.story = zentaoId(task["story"])
        draft.parent = zentaoId(task["parent"])
        draft.name = zentaoText(task["name"])
        draft.type = orDefault(task["type"], "devel")
        draft.pri = zentaoIntOr(task["pri"], 3)
        draft.estimate = zentaoNumber(task["estimate"])
        draft.left = zentaoNumber(task["left"])
        draft.consumed = zentaoNumber(task["consumed"])
        draft.status = orDefault(task["status"], "wait")
        draft.assignedTo = zentaoText(task["assignedTo"])
        draft.estStarted = zentaoDate(task["estStarted"])
        draft.deadline = zentaoDate(task["deadline"])
        draft.desc = str(task["desc"]) ?? ""
        draft.color = zentaoText(task["color"])
        draft.mailto = zentaoCsv(task["mailto"])
        draft.keywords = zentaoText(task["keywords"])
        draft.files = zentaoAttachments(ZenTaoEntity(json: task), baseUrl: client.baseUrl)
        var kept: [String: String] = [:]
        for field in keptTaskFields { kept[field] = str(task[field]) ?? "" }
        if legacy { kept[zentaoLegacyKey] = "1" }
        return TaskForm(draft: draft, options: taskOptions(page: p), kept: kept)
    }

    func taskOptions(_ executionId: String) async throws -> TaskFormOptions {
        taskOptions(page: try await page("task-create-\(executionId)-0-0"))
    }

    func taskOptions(page p: JSON) -> TaskFormOptions {
        let members = zentaoOptions(p["members"])
        var o = TaskFormOptions()
        o.executions = zentaoOptions(p["executions"])
        o.modules = zentaoOptions(firstNonNull(p["modulePairs"], p["moduleOptionMenu"], p["modules"]))
        o.stories = zentaoOptions(p["stories"])
        o.parents = zentaoOptions(firstNonNull(p["parents"], p["tasks"]))
        o.users = members.isEmpty ? zentaoOptions(p["users"]) : members
        return o
    }

    /// Saves `draft`; returns the task's ZenTao id (a new subtask's parent's when ZenTao does not say which id
    /// it got).
    func saveTask(_ form: TaskForm, _ draft: TaskDraft, uid: String) async throws -> String {
        if draft.id == nil && draft.parent != "0" { return try await saveSubtask(draft, uid: uid) }
        let legacy = form.kept[zentaoLegacyKey] == "1"
        let id = draft.id
        func hours(_ h: Double) -> String { h == h.rounded() ? "\(Int(h))" : "\(h)" }
        var f = ZenTaoForm()
        f.put("uid", uid)
        f.put("execution", draft.execution)
        f.put("module", draft.module)
        f.put("story", draft.story)
        f.put("name", draft.name)
        f.put("type", draft.type)
        f.put("pri", "\(draft.pri)")
        f.put("estimate", hours(draft.estimate))
        if !draft.estStarted.isEmpty { f.put("estStarted", draft.estStarted) }
        if !draft.deadline.isEmpty { f.put("deadline", draft.deadline) }
        f.put("desc", draft.desc)
        f.put("color", draft.color)
        f.put("mailto[]", list: draft.mailto)
        // 18.x's task table has no keywords column (an unknown key fails there).
        if !legacy { f.put("keywords", draft.keywords) }
        if id == nil {
            // 18.x creates nothing without an assignedTo list.
            if legacy { f.put("assignedTo[]", list: [draft.assignedTo]) } else { f.put("assignedTo", draft.assignedTo) }
        } else {
            f.put("assignedTo", draft.assignedTo)
            f.put("parent", draft.parent)
            f.put("status", draft.status)
            f.put("left", hours(draft.left))
            f.put("consumed", hours(draft.consumed))
            for field in keptTaskFields { if let v = form.kept[field], !v.isEmpty { f.put(field, v) } }
            f.put("deleteFiles[]", list: removedFiles(form.draft.files, draft.files))
        }
        let fromBug = form.kept[zentaoFromBugKey]
        let path = id == nil ? (fromBug.map { taskFromBugPath(draft.execution, bug: $0) } ?? "task-create-\(draft.execution)-0-0")
                             : "task-edit-\(id!)"
        let saved = try await post(path, f, draft.newFiles)
        if let id { return id }
        if let saved { return saved }
        throw Failure.parse("ZenTao gave no task id")
    }

    /// A new subtask, through the batch form. That form takes no attachments, CC or keywords, so a subtask
    /// given any is saved again through its edit form.
    private func saveSubtask(_ draft: TaskDraft, uid: String) async throws -> String {
        let res = try await client.classicPost(subtaskPath(draft), .form(subtaskRow(draft, uid: uid)))
        _ = try zentaoSaveResult(res.data)
        guard let id = batchCreatedId(res.data) else { return draft.parent }
        if !draft.newFiles.isEmpty || !draft.mailto.isEmpty || !draft.keywords.isEmpty {
            var edit = try await editTask(id)
            edit.draft.mailto = draft.mailto
            edit.draft.keywords = draft.keywords
            edit.draft.newFiles = draft.newFiles
            _ = try await saveTask(edit, edit.draft, uid: uid)
        }
        return id
    }
}
