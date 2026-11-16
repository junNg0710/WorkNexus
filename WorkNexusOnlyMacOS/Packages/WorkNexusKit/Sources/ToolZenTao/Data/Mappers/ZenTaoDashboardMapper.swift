import CoreDomain
import Foundation

// Ported from: lib/features/workspace_overview/data/mappers/zentao_dashboard_mapper.dart

/// The `fields` the dashboard asks `GET /user` for.
let kZenTaoDashboardFields = "task,bug,story,todo,execution,actions,contribute"
/// How many items each "my work" list holds.
let kZenTaoDashboardListLimit = 8

/// Parses a ZenTao `GET /user?fields=...` reply into a `ZenTaoDashboard`.
///
/// ZenTao's PHP serialises numbers as strings or ints, lists as arrays or id-keyed maps, and empty dates as
/// `0000-00-00`, and a block is simply absent when the user lacks the privilege - so every field is read
/// leniently and a missing block becomes an empty list.
func zenTaoDashboardFromJson(_ json: JSON, accountId: String, fetchedAt: Date) -> ZenTaoDashboard {
    var d = ZenTaoDashboard(accountId: accountId, profile: dashProfile(asMap(json["profile"]) ?? [:]), fetchedAt: fetchedAt)
    (d.tasks, d.taskTotal) = dashBlock(json["task"], "tasks", .task)
    (d.bugs, d.bugTotal) = dashBlock(json["bug"], "bugs", .bug)
    (d.stories, d.storyTotal) = dashBlock(json["story"], "stories", .story)
    (d.todos, d.todoTotal) = dashBlock(json["todo"], "todos", .todo)
    let execution = asMap(json["execution"])
    d.executions = dashList(execution?["executions"]).compactMap(dashExecution)
    d.executionTotal = dashInt(execution?["total"]) ?? d.executions.count
    d.activities = dashList(json["actions"]).compactMap(dashActivity)
    let contribute = asMap(json["contribute"])
    d.projectTotal = dashInt(contribute?["involvedProjectTotal"])
    d.productTotal = dashInt(contribute?["ownerProductTotal"])
    d.docTotal = dashInt(contribute?["docCreatedTotal"])
    return d
}

private func dashProfile(_ p: JSON) -> ZenTaoDashboardProfile {
    let account = dashStr(p["account"]) ?? ""
    let role = p["role"]
    let roleText = asMap(role).map { dashStr($0["name"]) ?? dashStr($0["code"]) } ?? dashStr(role)
    return ZenTaoDashboardProfile(account: account, realname: dashStr(p["realname"]) ?? account, role: roleText,
                                  email: dashStr(p["email"]), lastLogin: dashDate(p["last"]))
}

private func dashBlock(_ raw: Any?, _ key: String, _ kind: ZenTaoDashboardItemKind) -> ([ZenTaoDashboardWorkItem], Int) {
    let block = asMap(raw)
    let items = dashList(block?[key]).compactMap { dashItem($0, kind) }
    return (items, dashInt(block?["total"]) ?? items.count)
}

private func dashItem(_ e: JSON, _ kind: ZenTaoDashboardItemKind) -> ZenTaoDashboardWorkItem? {
    guard let id = dashStr(e["id"]) else { return nil }
    let context = ["executionName", "productName", "productTitle", "projectName"].lazy.compactMap { dashStr(e[$0]) }.first
    return ZenTaoDashboardWorkItem(
        kind: kind, id: id, title: dashStr(e["title"]) ?? dashStr(e["name"]) ?? "#\(id)",
        status: dashStr(e["status"])?.lowercased(), statusLabel: dashStr(e["statusName"]), priority: dashInt(e["pri"]),
        deadline: dashDate(e["deadline"]) ?? dashDate(e["date"]), context: context)
}

private func dashExecution(_ e: JSON) -> ZenTaoDashboardExecution? {
    guard let id = dashStr(e["id"]) else { return nil }
    let hours = asMap(e["hours"])
    return ZenTaoDashboardExecution(
        id: id, name: dashStr(e["name"]) ?? "#\(id)",
        projectName: dashStr(e["projectName"]) ?? dashStr(e["parentName"]), status: dashStr(e["status"])?.lowercased(),
        progress: dashDouble(e["progress"]) ?? dashDouble(hours?["progress"]), end: dashDate(e["end"]))
}

private func dashActivity(_ a: JSON) -> ZenTaoDashboardActivity? {
    guard let id = dashStr(a["id"]), let type = dashStr(a["objectType"]) else { return nil }
    let actor = a["actor"]
    let actorName = asMap(actor).map { dashStr($0["realname"]) ?? dashStr($0["account"]) } ?? dashStr(actor)
    return ZenTaoDashboardActivity(
        id: id, actor: actorName ?? "", action: dashStr(a["actionLabel"]) ?? dashStr(a["action"]) ?? "",
        objectType: type.lowercased(), objectId: dashStr(a["objectID"]) ?? dashStr(a["objectId"]) ?? "",
        objectName: dashStr(a["objectName"]), date: dashDate(a["date"]))
}

/// A JSON array or an id-keyed object, as a list of maps.
private func dashList(_ v: Any?) -> [JSON] { listOrMapValues(v).compactMap(asMap) }

private func dashStr(_ v: Any?) -> String? {
    if isNull(v) || asEntries(v) != nil || v is [Any] { return nil }
    let s = (str(v) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return s.isEmpty ? nil : s
}

private func dashInt(_ v: Any?) -> Int? {
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
    return Int(dashStr(v) ?? "")
}

private func dashDouble(_ v: Any?) -> Double? {
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
    return Double(dashStr(v) ?? "")
}

/// ZenTao's "no date" is `0000-00-00...`, and a future todo carries `2030-01-01`.
private func dashDate(_ v: Any?) -> Date? {
    guard let s = dashStr(v), !s.hasPrefix("0000"), !s.hasPrefix("2030-01-01") else { return nil }
    return ZenTaoDayParser.parse(s)
}
