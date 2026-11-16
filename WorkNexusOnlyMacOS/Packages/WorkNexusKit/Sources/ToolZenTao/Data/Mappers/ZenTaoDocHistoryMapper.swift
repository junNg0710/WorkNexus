import Foundation

// Ported from: lib/tools/zentao/data/mappers/zentao_doc_history_mapper.dart

/// `action-ajaxGetList-doc-{id}` -> the document's history, oldest first. An entry's `content` is ZenTao's
/// sentence for it - "2026-09-30 12:56:37, edited by <strong>ViPham-VN-go</strong> ." - and `historyChanges`
/// what changed.
func mapZenTaoDocHistory(_ json: JSON) -> [ZenTaoDocAction] {
    guard let raw = json["actions"] as? [Any] else { return [] }
    return raw.compactMap { item in
        guard let m = asMap(item), !isNull(m["id"]) else { return nil }
        return docAction(m)
    }
}

private let historyDatePrefix = try! NSRegularExpression(pattern: #"^\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}(?::\d{2})?),?"#)

private func docAction(_ item: JSON) -> ZenTaoDocAction {
    let content = str(item["content"]) ?? ""
    let ns = content as NSString
    let date = historyDatePrefix.firstMatch(in: content, range: NSRange(location: 0, length: ns.length))
    let sentence = HNode.parseFragment(date == nil ? content : ns.substring(from: date!.range.location + date!.range.length))
    let actor = sentence.firstElement("strong")?.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    let summary = sentence.plainText
        .replacingRegex(#"\s+"#, with: " ")
        .replacingRegex(#"\s*\.\s*$"#, with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    var when: Date?
    if let date { when = ZenTaoDayParser.parse(ns.substring(with: date.range(at: 1)).replacingOccurrences(of: " ", with: "T")) }
    return ZenTaoDocAction(
        id: str(item["id"]) ?? "", action: str(item["action"]) ?? "", summary: summary, date: when,
        actor: (actor ?? "").isEmpty ? nil : actor,
        changes: parseZenTaoDocChanges(str(item["historyChanges"]) ?? ""))
}

/// The fields ZenTao names as the document's body: their values are the editor's raw page (JSON), not something to read.
private let bodyFields: Set<String> = ["rawcontent", "content"]

private let wasIs = try! NSRegularExpression(pattern: #"It was "(.*)" and it is "(.*)""#, options: [.dotMatchesLineSeparators])

/// ZenTao's change list (`historyChanges`) - per field, `<strong><i>Field</i></strong> is changed. It was "a"
/// and it is "b".`, or "The difference is" and a `blockquote.textdiff` of `<del>` / `<ins>` lines (followed by
/// a copy, `blockquote.original`, that is skipped) - read field by field.
func parseZenTaoDocChanges(_ html: String) -> [ZenTaoDocChange] {
    if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
    let fragment = HNode.parseFragment(html)
    var out: [ZenTaoDocChange] = []
    var field: String?
    var text = ""
    var diff: HNode?

    func flush() {
        guard let name = field else { return }
        if bodyFields.contains(name.lowercased()) {
            out.append(ZenTaoDocChange(field: name, isBody: true))
        } else if let d = diff {
            func lines(_ tag: String) -> [String] {
                d.elements(tag).map { $0.plainText.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            out.append(ZenTaoDocChange(field: name, removed: lines("del"), added: lines("ins")))
        } else {
            let ns = text as NSString
            let m = wasIs.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
            out.append(ZenTaoDocChange(field: name, from: m.map { ns.substring(with: $0.range(at: 1)) },
                                       to: m.map { ns.substring(with: $0.range(at: 2)) }))
        }
        field = nil; diff = nil; text = ""
    }

    for node in fragment.children {
        if node.kind == .element, node.name == "strong", node.firstElement("i") != nil {
            flush()
            field = node.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if node.kind == .element, node.name == "blockquote" {
            if node.classes.contains("textdiff"), diff == nil { diff = node }
        } else {
            text += node.plainText
        }
    }
    flush()
    return out
}
