import CoreDomain
import Foundation

// Ported from: lib/tools/zentao/data/datasources/zentao_form_parsing.dart

private func lenientJSON(_ value: Any?) -> Any? {
    guard let s = value as? String else { return value }
    let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.hasPrefix("{") || text.hasPrefix("[") else { return nil }
    return try? jsonDecode(text)
}

/// The payload of a classic `.json` page: `{status, data}` where `data` is usually itself a JSON string; a bare
/// object passes through. Nil when the body is not JSON (an HTML login page, a PHP error).
func classicPayload(_ body: Any?) -> JSON? {
    var data = lenientJSON(body)
    guard let map = asMap(data) else { return nil }
    if !isNull(map["data"]), !isNull(map["status"]), let inner = asMap(lenientJSON(map["data"])) { data = inner }
    return asMap(data)
}

/// The payload of a classic ajax reply: like `classicPayload`, but a JSON list (20+'s picker items) passes
/// through too. Nil when the body is not JSON (18.x answers these with an HTML `<select>`).
func classicData(_ body: Any?) -> Any? {
    let data = lenientJSON(body)
    if let map = asMap(data), !isNull(map["data"]), !isNull(map["status"]) { return lenientJSON(map["data"]) }
    return data
}

private func formLabel(_ value: Any?) -> String? {
    guard let value, !(value is NSNull) else { return nil }
    if let map = asMap(value) { return formLabel(isNull(map["name"]) ? map["title"] : map["name"]) }
    return decodeHtmlEntities(str(value) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// A ZenTao `{id: name}` map as options, in its order. PHP sends a map whose keys happen to be 0...n-1 as a JSON
/// list, so lists are read by index. The "none" entries (`''`, `'0'`, a blank name) are left out: forms offer
/// their own "none".
func zentaoOptions(_ raw: Any?) -> [FormOption] {
    // 20+ may send a list as picker items rather than as a PHP list.
    if let list = raw as? [Any], asMap(list.first) != nil { return zentaoPickerOptions(raw) }
    let entries: [(String, Any?)]
    if let e = asEntries(raw) { entries = e.map { ($0.key, $0.value) } }
    else if let list = raw as? [Any] { entries = list.enumerated().map { ("\($0.offset)", $0.element) } }
    else { entries = [] }
    return entries.compactMap { key, value in
        guard !key.isEmpty, key != "0", key != "closed", let label = formLabel(value), !label.isEmpty else { return nil }
        return FormOption(value: key, label: label)
    }
}

/// `[{value, text}]` (ZenTao's ajax pickers) as options.
func zentaoPickerOptions(_ raw: Any?) -> [FormOption] {
    guard let list = raw as? [Any] else { return [] }
    return list.compactMap { item in
        guard let m = asMap(item) else { return nil }
        let value = str(isNull(m["value"]) ? "" : m["value"]) ?? ""
        guard !value.isEmpty, value != "0" else { return nil }
        // Pickers name the item `text`. A story with a grade (20+'s `addGradeLabel`) sends `text` as `{html}`
        // with a grade badge, and its plain title as `hint` / `keys`.
        let candidate: Any?
        if asMap(m["text"]) != nil {
            candidate = isNull(m["hint"]) ? m["keys"] : m["hint"]
        } else {
            candidate = !isNull(m["text"]) ? m["text"] : (!isNull(m["label"]) ? m["label"] : m["title"])
        }
        if let label = formLabel(candidate), !label.isEmpty { return FormOption(value: value, label: label) }
        return FormOption(value: value, label: value)
    }
}

/// A story / task label as ZenTao's pickers write it - `[C] 11983:Finisher:Name` (a subtask, its id, who
/// finished it, its name) - as `[C] #11983 Name`. The finisher is dropped only when it is one of `people` (real
/// names), since a name may itself hold a colon. A label without the id prefix is kept.
func zentaoLinkLabel(_ label: String, people: Set<String> = []) -> String {
    let ns = label as NSString
    guard let m = linkLabelRegex.firstMatch(in: label, range: NSRange(location: 0, length: ns.length)) else { return label }
    func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
    var name = group(3) ?? ""
    if let colon = name.firstIndex(of: ":"), colon > name.startIndex, people.contains(String(name[..<colon])) {
        name = String(name[name.index(after: colon)...])
    }
    return "\(group(1) ?? "")#\(group(2) ?? "") \(name.trimmingCharacters(in: .whitespacesAndNewlines))"
}

private let linkLabelRegex = try! NSRegularExpression(pattern: #"^(\[[^\]]*\] )?(\d+):(.*)$"#)

/// Task `task` from ZenTao's ajax list labelled with its plain `name` (from REST) - `[C] #11983 mobile` - keeping
/// the list's subtask mark. Without a name it falls back to `zentaoLinkLabel`.
func zentaoTaskLabel(_ task: FormOption, name: String?, people: Set<String> = []) -> String {
    guard let name, !name.isEmpty else { return zentaoLinkLabel(task.label, people: people) }
    var mark = ""
    if let r = task.label.range(of: #"^\[[^\]]*\] "#, options: .regularExpression) { mark = String(task.label[r]) }
    return "\(mark)#\(task.value) \(name)"
}

/// A field ZenTao stores as comma-separated text (builds, OS, mailto...).
func zentaoCsv(_ raw: Any?) -> [String] {
    if let list = raw as? [Any] {
        return list.compactMap { v in
            let s = (str(v) ?? "null").trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? nil : s
        }
    }
    guard let raw, !(raw is NSNull) else { return [] }
    return (str(raw) ?? "").split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// A ZenTao id field as text, `'0'` when unset.
func zentaoId(_ raw: Any?) -> String {
    let text = str(raw)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? "0" : text
}

/// A ZenTao date field (`Y-m-d`), empty when unset (`0000-00-00`).
func zentaoDate(_ raw: Any?) -> String {
    let text = str(raw)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if text.isEmpty || text.hasPrefix("0000") { return "" }
    return text.count > 10 ? String(text.prefix(10)) : text
}

/// A text field, entities decoded (ZenTao stores plain text HTML-escaped).
func zentaoText(_ raw: Any?) -> String { str(raw).map(decodeHtmlEntities) ?? "" }

func zentaoIntOr(_ raw: Any?, _ fallback: Int) -> Int { Int(str(raw) ?? "") ?? fallback }

func zentaoNumber(_ raw: Any?) -> Double { Double(str(raw) ?? "") ?? 0 }

/// The outcome of a classic create / edit POST: the new id on a create, or nil; throws a validation `Failure`
/// when ZenTao refused the form.
///
/// ZenTao 20+ answers bare JSON (`{result, message, id}`); 18.x wraps an edit's answer like a page
/// (`{status, data: "{\"locate\":...}"}`). An answer that is not JSON (a PHP or SQL error page) is a refusal too.
func zentaoSaveResult(_ body: Any?) throws -> String? {
    guard let reply = classicPayload(body) else { throw Failure.validation("ZenTao did not accept the form") }
    if str(reply["result"]) == "fail" || str(reply["status"]) == "fail" {
        let fields = fieldErrors(reply["message"])
        throw Failure.validation(fields.isEmpty ? (str(reply["message"]) ?? "ZenTao refused the form")
                                                 : fields.map(\.value).joined(separator: "\n"), fields: Dictionary(fields, uniquingKeysWith: { $1 }))
    }
    if let id = str(reply["id"]), !id.isEmpty, id != "0" { return id }
    // A duplicate on 18.x: the existing one's page.
    let locate = str(reply["locate"]) ?? str(reply["load"]) ?? ""
    let ns = locate as NSString
    if let m = try? NSRegularExpression(pattern: #"-view-(\d+)"#).firstMatch(in: locate, range: NSRange(location: 0, length: ns.length)) {
        return ns.substring(with: m.range(at: 1))
    }
    return nil
}

/// ZenTao's per-field errors (`{field: [msg...] | msg}`, or a list), keyed by field name without its `[]`.
private func fieldErrors(_ message: Any?) -> [(key: String, value: String)] {
    func text(_ v: Any?) -> String {
        if let l = v as? [Any] { return l.map { str($0) ?? "null" }.joined(separator: " ") }
        return str(v) ?? "null"
    }
    if let entries = asEntries(message) {
        return entries.map { ($0.key.replacingOccurrences(of: "[]", with: ""), zentaoText(text($0.value))) }
    }
    if let list = message as? [Any] { return list.enumerated().map { ("\($0.offset)", zentaoText(text($0.element))) } }
    return []
}
