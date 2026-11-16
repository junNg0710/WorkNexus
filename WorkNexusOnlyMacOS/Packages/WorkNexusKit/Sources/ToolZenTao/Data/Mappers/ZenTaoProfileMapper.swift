import Foundation

// Ported from: lib/tools/zentao/data/mappers/zentao_profile_mapper.dart

/// The stored/fetched `{profile: {...}, departments: [...]}` as a `ZenTaoProfile`. Throws `ZenTaoError.format`
/// when the reply has no profile.
func mapZenTaoProfile(accountId: String, _ json: JSON, baseUrl: String? = nil) throws -> ZenTaoProfile {
    guard let profile = asMap(json["profile"]) else { throw ZenTaoError.format("ZenTao profile is missing") }
    func value(_ key: String) -> String? {
        guard let t = str(profile[key])?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t != "0000-00-00" else { return nil }
        return t
    }
    let role = profile["role"]
    let roleMap = asMap(role)
    let roleName = roleMap != nil ? str(roleMap!["name"]) : str(role)
    var avatarUrl: String?
    if let avatar = value("avatar") {
        if let base = baseUrl.flatMap({ URL(string: $0) }), base.scheme != nil,
           let resolved = URL(string: avatar, relativeTo: base)?.absoluteURL { avatarUrl = resolved.absoluteString }
        else { avatarUrl = avatar }
    }
    var p = ZenTaoProfile(accountId: accountId, account: value("account") ?? "", realname: value("realname") ?? value("account") ?? "")
    p.userId = Int(value("id") ?? "")
    p.departmentId = Int(value("dept") ?? "")
    p.roleCode = roleMap.flatMap { str($0["code"]) }
    p.avatarUrl = avatarUrl
    p.gender = value("gender")
    p.department = value("departmentPath") ?? value("deptName")
    p.role = (roleName?.trimmingCharacters(in: .whitespaces).isEmpty == true) ? nil : roleName
    p.joined = value("join")
    p.privilege = value("privilege") ?? value("group")
    p.email = value("email")
    p.mobile = value("mobile")
    p.phone = value("phone")
    p.wechat = value("weixin")
    p.qq = value("qq")
    p.zipcode = value("zipcode")
    p.address = value("address")
    p.svnGitAccount = value("commiter")
    p.skype = value("skype")
    p.visits = Int(value("visits") ?? "")
    p.whatsapp = value("whatsapp")
    p.lastLogin = value("last")
    p.slack = value("slack")
    p.lastIp = value("ip")
    p.dingding = value("dingding")
    return p
}

func mapZenTaoDepartments(_ json: [JSON]) -> [ZenTaoDepartment] {
    json.compactMap { item in
        guard let id = Int(str(item["id"]) ?? "") else { return nil }
        return ZenTaoDepartment(id: id, name: str(item["name"]) ?? "", parentId: Int(str(item["parent"]) ?? "") ?? 0,
                                path: zenTaoDepartmentPath(id, json) ?? str(item["name"]) ?? "")
    }
}

/// Returns a readable hierarchy (e.g. "VN > Flutter VN") for a department id.
func zenTaoDepartmentPath(_ id: Int, _ departments: [JSON]) -> String? {
    if id <= 0 { return nil }
    var byId: [Int: JSON] = [:]
    for d in departments { if let i = Int(str(d["id"]) ?? "") { byId[i] = d } }
    var names: [String] = []
    var seen = Set<Int>()
    var current = id
    while current > 0, seen.insert(current).inserted {
        guard let d = byId[current] else { break }
        let name = (str(d["name"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { names.append(name) }
        current = Int(str(d["parent"]) ?? "") ?? 0
    }
    return names.isEmpty ? nil : names.reversed().joined(separator: " > ")
}
