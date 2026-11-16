import CoreDomain
import Foundation

// Ported from: lib/tools/zentao/data/models/zentao_subtask_form.dart

/// Where a new subtask of `draft`'s parent is posted: ZenTao's batch task form, the only one that takes a
/// parent task in 18.x to 21.x.
func subtaskPath(_ draft: TaskDraft) -> String {
    "task-batchCreate-\(draft.execution)-\(draft.story)-\(draft.module)-\(draft.parent)"
}

/// `draft` as the one row of ZenTao's batch task form. 18.x reads every column of a row, so all are sent.
func subtaskRow(_ draft: TaskDraft, uid: String) -> ZenTaoForm {
    var f = ZenTaoForm()
    f.put("uid", uid)
    f.put("parent[1]", draft.parent)
    f.put("name[1]", draft.name)
    f.put("type[1]", draft.type)
    f.put("pri[1]", "\(draft.pri)")
    f.put("estimate[1]", zentaoHours(draft.estimate))
    f.put("assignedTo[1]", draft.assignedTo)
    f.put("module[1]", draft.module)
    f.put("story[1]", draft.story)
    f.put("color[1]", draft.color)
    // 18.x turns a row's line breaks into <br>.
    f.put("desc[1]", draft.desc.replacingOccurrences(of: "\n", with: ""))
    if !draft.estStarted.isEmpty { f.put("estStarted[1]", draft.estStarted) }
    if !draft.deadline.isEmpty { f.put("deadline[1]", draft.deadline) }
    return f
}

/// The id ZenTao gave the first task of a batch (its `idList`), if it says.
func batchCreatedId(_ body: Any?) -> String? {
    for raw in listOrMapValues(classicPayload(body)?["idList"]) {
        let source: Any? = asMap(raw).map { isNull($0["id"]) ? $0["taskID"] : $0["id"] } ?? raw
        let id = (str(source) ?? "null").trimmingCharacters(in: .whitespaces)
        if !id.isEmpty, id != "0", id != "null" { return id }
    }
    return nil
}
