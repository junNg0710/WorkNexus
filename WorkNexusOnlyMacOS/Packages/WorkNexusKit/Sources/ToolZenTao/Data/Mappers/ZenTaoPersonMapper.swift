/// Ported from: lib/tools/zentao/data/mappers/zentao_person_mapper.dart
import CoreDomain
import Foundation

/// A colleague from `GET /users/{id}` as a `PersonProfile`. The reply is the bare user on most servers, wrapped in `user` or
/// `profile` on some; the department path comes from `departments` (`GET /departments`).
func mapZenTaoPerson(_ json: JSON, departments: [JSON] = []) -> PersonProfile {
    let user = asMap(json["user"]) ?? asMap(json["profile"]) ?? json
    func value(_ key: String) -> String? {
        let text = (str(user[key]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.hasPrefix("0000-00-00") ? nil : text
    }
    let role: String? = asMap(user["role"]).flatMap { blank($0["code"]) ?? blank($0["name"]) } ?? blank(user["role"])
    let deptId = Int(value("dept") ?? "") ?? 0
    return PersonProfile(
        department: zenTaoDepartmentPath(deptId, departments) ?? value("deptName") ?? value("departmentPath"),
        role: role, email: value("email"), mobile: value("mobile"), phone: value("phone"), gender: value("gender"),
        address: value("address"), joined: zenTaoPersonDate(user["join"]), lastLogin: zenTaoPersonDate(user["last"]),
        wechat: value("weixin"), qq: value("qq"), skype: value("skype"), slack: value("slack"), whatsapp: value("whatsapp"),
        dingding: value("dingding"))
}

private func blank(_ v: Any?) -> String? {
    let text = (str(v) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
}

/// ZenTao sends dates as `2024-03-01`, `2024-03-01 09:30:00`, ISO strings or Unix seconds; `0000-00-00` and 0 mean "never".
func zenTaoPersonDate(_ v: Any?) -> Date? {
    if let n = v as? NSNumber, !(v is Bool) { return n.doubleValue <= 0 ? nil : Date(timeIntervalSince1970: n.doubleValue) }
    guard let text = blank(v), !text.hasPrefix("0000") else { return nil }
    if let seconds = Double(text) { return seconds <= 0 ? nil : Date(timeIntervalSince1970: seconds) }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
        f.dateFormat = format
        if let d = f.date(from: text) { return d }
    }
    return ISO8601DateFormatter().date(from: text)
}
