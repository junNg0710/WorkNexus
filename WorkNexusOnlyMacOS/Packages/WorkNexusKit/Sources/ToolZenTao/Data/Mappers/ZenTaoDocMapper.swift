import CoreDomain
import Foundation

// Ported from: lib/tools/zentao/data/mappers/zentao_doc_mapper.dart

/// `GET /doclibs` -> `{libs: [{id, name}]}`.
func mapZenTaoDocLibs(_ json: JSON) -> [ZenTaoDocLib] {
    docItems(json["libs"]).compactMap { item in
        docId(item["id"]).map { ZenTaoDocLib(id: $0, name: docLabel(item["name"]) ?? $0) }
    }
}

/// `GET /docs?lib={libId}` -> `{docs: [...]}` (a list, or an id-keyed map).
func mapZenTaoDocSummaries(_ json: JSON, libId: String) -> [ZenTaoDocSummary] {
    docItems(json["docs"]).compactMap { item in
        docId(item["id"]).map { ZenTaoDocSummary(id: $0, title: docLabel(item["title"]) ?? $0, libId: libId, acl: docText(item["acl"])) }
    }
}

/// `GET /docs/{id}` -> the document. Nil when the reply has no document - ZenTao answers a document the user may
/// not read (or a deleted one) with an object that lacks its fields.
func mapZenTaoDoc(_ json: JSON, baseUrl: String) -> ZenTaoDoc? {
    guard let id = docId(json["id"]) else { return nil }
    // `/docs/{id}` sends `files` as a list, where bugs and tasks send an id-keyed map - the shape the shared
    // attachment mapper reads.
    var files: JSON = [:]
    for (i, file) in docItems(json["files"]).enumerated() { files[str(file["id"]) ?? "\(i)"] = file }
    return ZenTaoDoc(
        id: id, title: docLabel(json["title"]) ?? id, libId: docId(json["lib"]) ?? "",
        html: tidyZenTaoDocHtml(json["content"] as? String ?? ""),
        isAttachment: str(json["type"]) == "attachment", version: Int(str(json["version"]) ?? ""),
        author: docPerson(json["addedBy"]), editors: docEditors(json), views: Int(str(json["views"]) ?? ""),
        addedDate: parseZenTaoDate(json["addedDate"]), editedDate: parseZenTaoDate(json["editedDate"]),
        files: zentaoAttachments(ZenTaoEntity(json: ["files": files]), baseUrl: baseUrl))
}

private func docItems(_ raw: Any?) -> [JSON] { listOrMapValues(raw).compactMap(asMap) }

private func docId(_ raw: Any?) -> String? {
    let s = str(raw)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return s.isEmpty || s == "0" ? nil : s
}

/// A name or title as ZenTao stores it, HTML-escaped (`Post &amp; Restriction`), read back as plain text.
private func docLabel(_ raw: Any?) -> String? {
    guard let s = docText(raw) else { return nil }
    return docText(HNode.parseFragment(s).plainText)
}

private func docText(_ raw: Any?) -> String? {
    let s = str(raw)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return s.isEmpty ? nil : s
}

/// A person is sent bare (`"thanh"`) or as `{account, realname, ...}`.
private func docPerson(_ raw: Any?) -> ZenTaoDocPerson? {
    if let m = asMap(raw) { return docText(m["account"]).map { ZenTaoDocPerson(account: $0, name: docText(m["realname"])) } }
    return docText(raw).map { ZenTaoDocPerson(account: $0) }
}

/// `editedList` (`,Tompham,Tom,Tommy`) names every editor by login; the last editor (`editedBy`) also comes with
/// a display name.
private func docEditors(_ json: JSON) -> [ZenTaoDocPerson] {
    let last = docPerson(json["editedBy"])
    var accounts = (str(json["editedList"]) ?? "").split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    if let last { accounts.append(last.account) }
    var seen = Set<String>()
    return accounts.compactMap { a in
        seen.insert(a.lowercased()).inserted ? (a == last?.account ? last! : ZenTaoDocPerson(account: a)) : nil
    }
}

/// The locally stored pins (written by `zenTaoDocPinsToJson`). Names are stored already decoded.
func mapZenTaoDocPins(_ json: JSON) -> ZenTaoDocPins {
    ZenTaoDocPins(
        libs: docItems(json["libs"]).compactMap { i in docId(i["id"]).map { ZenTaoDocLib(id: $0, name: docText(i["name"]) ?? $0) } },
        docs: docItems(json["docs"]).compactMap { i in
            docId(i["id"]).map { ZenTaoDocSummary(id: $0, title: docText(i["title"]) ?? $0, libId: docText(i["libId"]) ?? "", acl: docText(i["acl"])) }
        })
}

func zenTaoDocPinsToJson(_ pins: ZenTaoDocPins) -> JSON {
    [
        "libs": pins.libs.map { ["id": $0.id, "name": $0.name] as JSON },
        "docs": pins.docs.map { d -> JSON in
            var j: JSON = ["id": d.id, "title": d.title, "libId": d.libId]
            if let acl = d.acl { j["acl"] = acl }
            return j
        },
    ]
}
