import CoreDomain
import Foundation

// Ported from: lib/tools/zentao/data/models/zentao_ticket_forms.dart

/// Marks, in a form's `kept` fields, that it came from ZenTao 18.x - whose forms differ (field names, which
/// keys it accepts) from 20+.
let zentaoLegacyKey = "_legacy"

/// Bug fields an edit must send back unchanged, or ZenTao resets them (and reopens a resolved or closed bug).
let keptBugFields = ["status", "resolution", "resolvedBy", "resolvedDate", "resolvedBuild", "closedBy", "closedDate",
                     "duplicateBug", "feedbackBy", "notifyEmail", "testtask", "case", "lastEditedDate"]

/// Task fields an edit must send back unchanged.
let keptTaskFields = ["mode", "realStarted", "finishedBy", "finishedDate", "canceledBy", "canceledDate", "closedBy",
                      "closedReason", "closedDate", "lastEditedDate"]

/// First non-null of `values` (Dart `a ?? b ?? c`).
func firstNonNull(_ values: Any?...) -> Any? { values.first { !isNull($0) } ?? nil }

/// Loads and saves ZenTao's own bug and task forms (its classic web actions: `bug-create` / `bug-edit` /
/// `task-create` / `task-edit`), so what is saved is checked exactly as on the web. 18.x and 20+ differ: see
/// the notes in each method.
struct ZenTaoTicketForms {
    let client: ZenTaoClient

    func page(_ path: String) async throws -> JSON {
        guard let payload = classicPayload(try await client.classicGet(path).data) else {
            throw Failure.notFound("ZenTao did not return the form (\(path))")
        }
        return payload
    }

    // MARK: People

    /// Product `productId`'s members - the people its new bug form lets a bug go to.
    func productMembers(_ productId: String) async throws -> [FormOption] {
        let p = try await page("bug-create-\(productId)-0-")
        let bug = asMap(p["bug"]) ?? [:]
        return zentaoOptions(firstNonNull(p["productMembers"], p["assignedToList"], bug["productMembers"]))
    }

    /// Execution `executionId`'s team, as its new task form lists it.
    func executionMembers(_ executionId: String) async throws -> [FormOption] {
        zentaoOptions(try await page("task-create-\(executionId)-0-0")["members"])
    }

    // MARK: Bugs

    /// A new bug's form in product `productId` (`'0'`: ZenTao picks its current one), filled in by ZenTao from
    /// bug `copyOf` (a copy), or filed against execution `executionId` and task `taskId` - the `extras` its web
    /// form takes in both 18.x and 20+.
    func newBug(_ productIdIn: String, copyOf: String? = nil, executionId: String? = nil, taskId: String? = nil) async throws -> BugForm {
        var productId = productIdIn
        // ZenTao takes nothing from the task but its id, and with no product it opens its first one, so a bug
        // from a task names the task's own scope.
        let scope: TaskScope? = (productId == "0" && taskId != nil) ? await taskScope(taskId!, executionId) : nil
        if let scoped = scope?.product { productId = scoped }
        var extras: [String] = []
        if let copyOf { extras.append("bugID=\(copyOf)") }
        if let p = scope?.project { extras.append("projectID=\(p)") }
        if let e = scope?.execution ?? executionId { extras.append("executionID=\(e)") }
        if let taskId { extras.append("taskID=\(taskId)") }
        if let s = scope?.story { extras.append("storyID=\(s)") }
        let p = try await page("bug-create-\(productId)-0-\(extras.joined(separator: ","))")
        let legacy = p["bugTitle"] != nil
        // 20+ keeps the defaults on an init `bug`; 18.x sends them flat.
        let bug = asMap(p["bug"]) ?? p
        let product = productId != "0" ? productId : zentaoId(firstNonNull(p["productID"], bug["productID"]))
        let execution = zentaoId(firstNonNull(bug["executionID"], p["executionID"], idOf(p["execution"])))
        var draft = BugDraft(product: product)
        draft.module = zentaoId(firstNonNull(bug["moduleID"], p["moduleID"]))
        draft.project = zentaoId(firstNonNull(bug["projectID"], p["projectID"]))
        draft.execution = execution
        draft.story = zentaoId(firstNonNull(bug["storyID"], p["storyID"]))
        draft.task = zentaoId(firstNonNull(bug["taskID"], p["taskID"]))
        // A copy keeps its builds; a new bug starts on trunk.
        let builds = zentaoCsv(firstNonNull(bug["buildID"], p["buildID"])).filter { $0 != "0" }
        draft.openedBuilds = builds.isEmpty ? ["trunk"] : builds
        // 18.x's own `title` is the page's; a copied one is `bugTitle`.
        draft.title = zentaoText(legacy ? p["bugTitle"] : bug["title"])
        draft.type = orDefault(bug["type"], "codeerror")
        draft.severity = zentaoIntOr(bug["severity"], 3)
        draft.pri = zentaoIntOr(bug["pri"], 3)
        // 18.x sends the steps template HTML-escaped.
        draft.steps = zentaoText(bug["steps"])
        draft.assignedTo = zentaoText(bug["assignedTo"])
        draft.deadline = zentaoDate(bug["deadline"])
        draft.os = zentaoCsv(bug["os"])
        draft.browser = zentaoCsv(bug["browser"])
        draft.mailto = zentaoCsv(bug["mailto"])
        draft.keywords = zentaoText(bug["keywords"])
        draft.color = zentaoText(bug["color"])
        return BugForm(draft: draft, options: await withLinkOptions(bugOptions(page: p), productId: product, executionId: execution),
                       kept: legacy ? [zentaoLegacyKey: "1"] : [:])
    }

    func editBug(_ bugId: String) async throws -> BugForm {
        let p = try await page("bug-edit-\(bugId)")
        let legacy = p["openedBuilds"] == nil
        guard let bug = asMap(p["bug"]) else { throw Failure.notFound("ZenTao bug \(bugId) not found") }
        var draft = BugDraft(id: bugId, product: zentaoId(bug["product"]))
        draft.branch = zentaoId(bug["branch"])
        draft.module = zentaoId(bug["module"])
        draft.project = zentaoId(bug["project"])
        draft.execution = zentaoId(bug["execution"])
        draft.plan = zentaoId(bug["plan"])
        draft.openedBuilds = zentaoCsv(bug["openedBuild"])
        draft.assignedTo = zentaoText(bug["assignedTo"])
        draft.deadline = zentaoDate(bug["deadline"])
        draft.type = orDefault(bug["type"], "codeerror")
        draft.os = zentaoCsv(bug["os"])
        draft.browser = zentaoCsv(bug["browser"])
        draft.title = zentaoText(bug["title"])
        draft.color = zentaoText(bug["color"])
        draft.severity = zentaoIntOr(bug["severity"], 3)
        draft.pri = zentaoIntOr(bug["pri"], 3)
        draft.steps = str(bug["steps"]) ?? ""
        draft.story = zentaoId(bug["story"])
        draft.task = zentaoId(bug["task"])
        draft.mailto = zentaoCsv(bug["mailto"])
        draft.keywords = zentaoText(bug["keywords"])
        draft.files = zentaoAttachments(ZenTaoEntity(json: bug), baseUrl: client.baseUrl)
        // 18.x's edit page has no builds or stories: the create page has them.
        var options = bugOptions(page: p)
        if legacy || options.builds.isEmpty {
            let extra = try await bugOptions(draft.product, projectId: draft.project, executionId: draft.execution)
            if options.builds.isEmpty { options.builds = extra.builds }
            if options.stories.isEmpty { options.stories = extra.stories }
            if options.tasks.isEmpty { options.tasks = extra.tasks }
        } else {
            options = await withLinkOptions(options, productId: draft.product, executionId: draft.execution)
        }
        var kept: [String: String] = [:]
        for field in keptBugFields { kept[field] = str(bug[field]) ?? "" }
        kept["related"] = str(firstNonNull(bug["relatedBug"], bug["linkBug"])) ?? ""
        if legacy { kept[zentaoLegacyKey] = "1" }
        return BugForm(draft: draft, options: options, kept: kept)
    }

    func bugOptions(_ productId: String, projectId: String = "0", executionId: String = "0") async throws -> BugFormOptions {
        let p = try await page("bug-create-\(productId)-0-projectID=\(projectId),executionID=\(executionId)")
        return await withLinkOptions(bugOptions(page: p), productId: productId, executionId: executionId)
    }

    /// Product `productId`'s bug modules - the form page's list alone, without the stories and tasks
    /// `bugOptions` also loads.
    func bugModules(_ productId: String) async throws -> [FormOption] {
        bugOptions(page: try await page("bug-create-\(productId)-0-projectID=0,executionID=0")).modules
    }

    /// Saves `draft`; returns the bug's ZenTao id.
    func saveBug(_ form: BugForm, _ draft: BugDraft, uid: String) async throws -> String {
        let legacy = form.kept[zentaoLegacyKey] == "1"
        let id = draft.id
        var f = ZenTaoForm()
        f.put("uid", uid)
        f.put("product", draft.product)
        f.put("branch", draft.branch)
        f.put("module", draft.module)
        f.put("project", draft.project)
        f.put("execution", draft.execution)
        f.put("plan", draft.plan)
        f.put("openedBuild[]", list: draft.openedBuilds)
        f.put("assignedTo", draft.assignedTo)
        // An empty date is left out: ZenTao fills in its own "none".
        if !draft.deadline.isEmpty { f.put("deadline", draft.deadline) }
        f.put("type", draft.type)
        f.put("os[]", list: draft.os)
        f.put("browser[]", list: draft.browser)
        f.put("title", draft.title)
        f.put("color", draft.color)
        f.put("severity", "\(draft.severity)")
        f.put("pri", "\(draft.pri)")
        f.put("steps", draft.steps)
        f.put("story", draft.story)
        f.put("task", draft.task)
        f.put("mailto[]", list: draft.mailto)
        f.put("keywords", draft.keywords)
        if id != nil {
            for field in keptBugFields { f.put(field, form.kept[field]) }
            let related = zentaoCsv(form.kept["related"])
            if !related.isEmpty { f.put(legacy ? "linkBug[]" : "relatedBug[]", list: related) }
            f.put("deleteFiles[]", list: removedFiles(form.draft.files, draft.files))
        }
        let path = id == nil ? "bug-create-\(draft.product)-\(draft.branch)-" : "bug-edit-\(id!)"
        let saved = try await post(path, f, draft.newFiles)
        if let id { return id }
        if let saved { return saved }
        throw Failure.parse("ZenTao gave no bug id")
    }

    // MARK: Shared

    /// Uploads an image for a description; returns the URL to embed it at.
    func uploadImage(uid: String, bytes: Data, name: String) async throws -> String {
        let res = try await client.classicPost("file-ajaxUpload-\(uid)",
                                               .multipart(fields: ZenTaoForm(), files: [("imgFile", DraftFile(name: name, bytes: bytes))]))
        let reply = classicPayload(res.data)
        let url = str(reply?["url"]) ?? ""
        if url.isEmpty || (str(reply?["error"]) ?? "0") != "0" {
            throw Failure.validation(str(reply?["message"]) ?? "ZenTao did not take the image")
        }
        // ZenTao answers a path under its web root.
        if URL(string: url)?.scheme != nil { return url }
        guard let base = URL(string: client.baseUrl), let resolved = URL(string: url, relativeTo: base)?.absoluteURL else { return url }
        return resolved.absoluteString
    }

    func post(_ path: String, _ fields: ZenTaoForm, _ files: [DraftFile]) async throws -> String? {
        var body: ZenTaoBody = .form(fields)
        if !files.isEmpty {
            var f = fields
            f.put("labels[]", list: files.map(\.name))
            body = .multipart(fields: f, files: files.map { ("files[]", $0) })
        }
        return try zentaoSaveResult(try await client.classicPost(path, body).data)
    }
}

/// The ids of the `loaded` attachments no longer in `kept`.
func removedFiles(_ loaded: [TicketAttachment], _ kept: [TicketAttachment]) -> [String] {
    loaded.filter { !kept.contains($0) }.map(\.id)
}

/// The id of a ZenTao object given whole (`{id, name...}`), as 18.x gives the current execution.
func idOf(_ raw: Any?) -> Any? { asMap(raw)?["id"] }

func orDefault(_ raw: Any?, _ fallback: String) -> String {
    let text = str(raw)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? fallback : text
}
