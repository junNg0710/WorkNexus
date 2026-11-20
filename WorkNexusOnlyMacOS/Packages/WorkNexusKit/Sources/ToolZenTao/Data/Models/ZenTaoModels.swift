import Foundation

// Ported from: lib/tools/zentao/data/models/zentao_models.dart
// JSON DTOs for the ZenTao REST v1 API (deserialize-only). ZenTao's payloads are loosely typed - numbers arrive
// as ints or strings, `assignedTo`/`actor` as a bare string or an `{account, realname}` object, and `actions` as
// a list or an id-keyed map - so union-shaped fields stay `Any?` and are read leniently. These DTOs never leave
// the data layer (rule 3.3): the adapter maps them to domain entities at the boundary.

/// ZenTao returns `actions` as a JSON array or an id-keyed object; both become a chronologically sorted list.
func zentaoActions(_ raw: Any?) -> [ZenTaoAction] {
    var values: [Any]
    if let list = raw as? [Any] {
        values = list
    } else if asEntries(raw) != nil {
        values = listOrMapValues(raw).sorted { (zentaoInt(asMap($0)?["id"]) ?? 0) < (zentaoInt(asMap($1)?["id"]) ?? 0) }
    } else {
        return []
    }
    values = values.filter { asMap($0) != nil }
    return values.compactMap { asMap($0).map(ZenTaoAction.init(json:)) }
}

/// A parent task's `children` - a list, or an id-keyed object - in id order.
func zentaoChildren(_ raw: Any?) -> [ZenTaoEntity] {
    listOrMapValues(raw).compactMap { asMap($0).map(ZenTaoEntity.init(json:)) }
        .sorted { (zentaoInt($0.id) ?? 0) < (zentaoInt($1.id) ?? 0) }
}

/// ZenTao returns `files` as an id-keyed object; normalised to a list ordered by ascending id (upload order).
func zentaoFiles(_ raw: Any?) -> [ZenTaoFile] {
    guard asEntries(raw) != nil else { return [] }
    return listOrMapValues(raw).compactMap(asMap)
        .sorted { (zentaoInt($0["id"]) ?? 0) < (zentaoInt($1["id"]) ?? 0) }
        .map(ZenTaoFile.init(json:))
}

/// A file attached to a ZenTao object (`bug.files[<id>]`).
struct ZenTaoFile {
    let json: JSON
    init(json: JSON) { self.json = json }
    var id: Any? { json["id"] }
    var title: Any? { json["title"] }
    var name: Any? { json["name"] }
    var `extension`: Any? { json["extension"] }
    var size: Int? { zentaoInt(json["size"]) }
    var url: Any? { json["url"] }
    /// The file's static path under the web root (`/zentao/data/upload/...`).
    var webPath: Any? { json["webPath"] }
    var addedBy: Any? { json["addedBy"] }
    var addedDate: Any? { json["addedDate"] }
}

/// One entry in a ticket's action/history collection.
struct ZenTaoAction {
    let json: JSON
    init(json: JSON) { self.json = json }
    var id: Any? { json["id"] }
    var action: Any? { json["action"] }
    var actor: Any? { json["actor"] }          // String | { account, realname }
    var comment: Any? { json["comment"] }
    var date: Any? { json["date"] }
    var extra: Any? { json["extra"] }          // String | object (assignee / resolution / ...)
    var actionType: String { str(action)?.lowercased() ?? "" }
    var commentText: String { str(comment) ?? "" }
}

/// A ZenTao bug / task / story object. Fields differ by kind (title vs name, steps vs desc vs spec) and are
/// read leniently by `normalizeZenTao`.
struct ZenTaoEntity {
    let json: JSON
    let children: [ZenTaoEntity]
    let files: [ZenTaoFile]
    let actions: [ZenTaoAction]

    init(json: JSON = [:]) {
        self.json = json
        children = zentaoChildren(json["children"])
        files = zentaoFiles(json["files"])
        actions = zentaoActions(json["actions"])
    }

    private subscript(key: String) -> Any? { isNull(json[key]) ? nil : json[key] }

    var id: Any? { self["id"] }
    var title: Any? { self["title"] }
    var name: Any? { self["name"] }
    var steps: Any? { self["steps"] }
    var desc: Any? { self["desc"] }
    var description: Any? { self["description"] }
    var spec: Any? { self["spec"] }
    var status: Any? { self["status"] }
    var resolution: Any? { self["resolution"] }
    var type: Any? { self["type"] }
    var os: Any? { self["os"] }
    var browser: Any? { self["browser"] }
    var pri: Int? { zentaoInt(self["pri"]) }
    var confirmed: Int? { zentaoInt(self["confirmed"]) }
    var severity: Int? { zentaoInt(self["severity"]) }
    var keywords: Any? { self["keywords"] }
    var assignedTo: Any? { self["assignedTo"] }
    var openedBy: Any? { self["openedBy"] }
    var openedDate: Any? { self["openedDate"] }
    var openedBuild: Any? { self["openedBuild"] }
    var assignedDate: Any? { self["assignedDate"] }
    var deadline: Any? { self["deadline"] }
    var resolvedBy: Any? { self["resolvedBy"] }
    var resolvedDate: Any? { self["resolvedDate"] }
    var resolvedBuild: Any? { self["resolvedBuild"] }
    var closedBy: Any? { self["closedBy"] }
    var closedDate: Any? { self["closedDate"] }
    var lastEditedBy: Any? { self["lastEditedBy"] }
    var lastEditedDate: Any? { self["lastEditedDate"] }
    var productName: Any? { self["productName"] }
    var projectName: Any? { self["projectName"] }
    var executionName: Any? { self["executionName"] }
    var storyTitle: Any? { self["storyTitle"] }
    /// A task's parent task id: > 0 on a subtask (0 none, -1 a parent itself).
    var parent: Int? { zentaoInt(self["parent"]) }
    /// 1 on a parent task (ZenTao 20+; 18.x marks one with `parent` -1).
    var isParent: Int? { zentaoInt(self["isParent"]) }
    var parentName: Any? { self["parentName"] }
    /// A task's hours: estimated, logged so far, and left.
    var estimate: Double? { zentaoDouble(self["estimate"]) }
    var consumed: Double? { zentaoDouble(self["consumed"]) }
    var left: Double? { zentaoDouble(self["left"]) }
    var realStarted: Any? { self["realStarted"] }
    var estStarted: Any? { self["estStarted"] }
    var fromBug: Any? { self["fromBug"] }
    var finishedBy: Any? { self["finishedBy"] }
    var finishedDate: Any? { self["finishedDate"] }
    var taskName: Any? { self["taskName"] }
    var planName: Any? { self["planName"] }
    var product: Any? { self["product"] }
    var project: Any? { self["project"] }
    var execution: Any? { self["execution"] }
    var branch: Any? { self["branch"] }
    var module: Any? { self["module"] }
    var story: Any? { self["story"] }
    var task: Any? { self["task"] }
    var plan: Any? { self["plan"] }
    var activatedCount: Int? { zentaoInt(self["activatedCount"]) }

    /// The ZenTao id as a string (`''` when absent).
    var idString: String { str(id) ?? "" }

    /// The first non-null of the product/project/execution name candidates.
    var scopeName: String {
        str(productName ?? projectName ?? executionName ?? product ?? project ?? execution) ?? ""
    }
}

/// `GET /users` -> `{ users: [...] }`.
struct ZenTaoUser {
    var id: String?
    var account: String?
    var realname: String?
    /// The department the user sits in (0 or nil: none).
    var dept: Int? = nil
}

struct ZenTaoUsersResponse {
    var users: [ZenTaoUser]
    /// How many users the server has, when it says.
    var total: Int?
    init(json: JSON) {
        total = zentaoInt(json["total"])
        users = (json["users"] as? [Any] ?? []).compactMap { raw -> ZenTaoUser? in
            guard let m = asMap(raw) else { return nil }
            return ZenTaoUser(id: zentaoInt(m["id"]).map(String.init), account: m["account"] as? String, realname: m["realname"] as? String,
                              dept: zentaoInt(m["dept"]))
        }
    }
}

/// `GET /products/{id}/bugs` and the classic bug views -> `{ total, bugs }`.
struct ZenTaoProductBugsResponse {
    var total: Int
    var bugs: [ZenTaoEntity]
    init(total: Int, bugs: [ZenTaoEntity]) { self.total = total; self.bugs = bugs }
    init(json: JSON) {
        total = zentaoInt(json["total"]) ?? 0
        bugs = (json["bugs"] as? [Any] ?? []).compactMap { asMap($0).map(ZenTaoEntity.init(json:)) }
    }
}

/// A ZenTao execution (sprint/iteration) from `GET /projects/{id}/executions`.
struct ZenTaoExecution {
    var id: String
    var name: String
    init(json: JSON) {
        id = str(json["id"]) ?? ""
        name = str(isNull(json["name"]) ? json["title"] : json["name"]) ?? id
    }
}

struct ZenTaoExecutionsResponse {
    var total: Int
    var executions: [ZenTaoExecution]
    init(json: JSON) {
        total = zentaoInt(json["total"]) ?? 0
        executions = (json["executions"] as? [Any] ?? []).compactMap { asMap($0).map(ZenTaoExecution.init(json:)) }
    }
}

/// One page of the classic `execution-task-...json` view -> `{ tasks, pager }`.
struct ZenTaoExecutionTasksResponse {
    var total: Int
    /// The page's tasks, each parent followed by its subtasks.
    var tasks: [ZenTaoEntity]
    init(total: Int, tasks: [ZenTaoEntity]) { self.total = total; self.tasks = tasks }

    init(classicView view: JSON) {
        var out: [ZenTaoEntity] = []
        func collect(_ raw: Any?) {
            for t in listOrMapValues(raw) {
                guard let m = asMap(t) else { continue }
                out.append(ZenTaoEntity(json: m))
                collect(m["children"])
            }
        }
        collect(view["tasks"])
        tasks = out
        total = asMap(view["pager"]).flatMap { zentaoInt($0["recTotal"]) } ?? out.count
    }
}

/// One `{ total, <bugs|tasks|stories>: [...] }` group inside the `GET /user` (assigned-to-me) response. The
/// list key varies by kind, so this reads the first list value in the group rather than a fixed key.
struct ZenTaoAssignedGroup {
    var total: Int
    var items: [ZenTaoEntity]
    init(group: Any?) {
        let json = asMap(group) ?? [:]
        // The first list value in the group (the list key varies by kind).
        let list = (asEntries(group) ?? []).lazy.compactMap { $0.value as? [Any] }.first ?? []
        total = zentaoInt(json["total"]) ?? 0
        items = list.compactMap { asMap($0).map(ZenTaoEntity.init(json:)) }
    }
}

/// `GET /user?type=assignedTo&fields=<bug|task|story>` -> `{ profile, bug: {...}, task: {...}, story: {...} }`.
struct ZenTaoAssignedResponse {
    var bug: ZenTaoAssignedGroup?
    var task: ZenTaoAssignedGroup?
    var story: ZenTaoAssignedGroup?
    init(json: JSON) {
        bug = asMap(json["bug"]) == nil ? nil : ZenTaoAssignedGroup(group: json["bug"])
        task = asMap(json["task"]) == nil ? nil : ZenTaoAssignedGroup(group: json["task"])
        story = asMap(json["story"]) == nil ? nil : ZenTaoAssignedGroup(group: json["story"])
    }
    /// The group for a ZenTao `fields` value (`bug` / `task` / `story`).
    func group(for field: String) -> ZenTaoAssignedGroup? {
        switch field { case "bug": bug; case "task": task; case "story": story; default: nil }
    }
}
