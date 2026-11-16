import CoreDomain
import Foundation

// Ported from: lib/tools/zentao/data/mappers/zentao_normalize.dart

/// Maps a ZenTao raw status (+ confirmed for bugs) to the unified status, per the researched DevLake-informed mapping.
func mapZenTaoStatus(_ type: ZenTaoType, _ raw: String, confirmed: Int? = nil) -> UnifiedStatus {
    switch type {
    case .bug:
        switch raw {
        case "active": return confirmed == 1 ? .todo : .inbox
        case "resolved": return .review
        case "closed": return .done
        default: return .inbox
        }
    case .task:
        switch raw {
        case "wait": return .todo
        case "doing": return .inprogress
        case "pause": return .blocked
        case "done": return .review
        case "closed", "cancel": return .done
        default: return .todo
        }
    case .story:
        switch raw {
        case "draft": return .inbox
        case "reviewing": return .review
        case "changing": return .inprogress
        case "active": return .todo
        case "closed": return .done
        default: return .inbox
        }
    }
}

/// ZenTao `pri` (1 highest ... 4 low; 0/unset -> medium) -> unified priority.
func mapZenTaoPriority(_ pri: Int?) -> Priority {
    guard let pri, pri != 0 else { return .medium }
    return Priority.fromLevel(min(max(pri - 1, 0), 3))
}

/// Crudely strips HTML tags + decodes a few entities for a plaintext body.
func stripHtml(_ html: String) -> String {
    html.replacingRegex("<[^>]*>", with: "")
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingRegex(#"\n{3,}"#, with: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Parses ZenTao dates (ISO-8601 or `YYYY-MM-DD HH:MM:SS`); `0000-00-00` -> nil.
func parseZenTaoDate(_ value: Any?) -> Date? {
    guard let s = str(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, !s.hasPrefix("0000-00-00") else { return nil }
    // Dart: `s.replaceFirst(' ', 'T')`.
    var t = s
    if let sp = t.firstIndex(of: " ") { t.replaceSubrange(sp...sp, with: "T") }
    return ZenTaoDayParser.parse(t)
}

/// Human-readable phrase for a ZenTao action/history record, rendered after the actor's name (e.g. "assigned to
/// Thanh", "resolved · resolution: Fixed"). Mirrors ZenTao's own history descriptions.
func zentaoActionText(_ action: ZenTaoAction) -> String {
    let a = action.actionType
    let extra = action.extra
    let extraStr = (extra as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    switch a {
    case "opened": return "created"
    case "assigned", "assignedto":
        let to = accountName(extra)
        return (to ?? "").isEmpty ? "assigned" : "assigned to \(to!)"
    case "resolved":
        let r = zentaoResolutionLabel(extraStr) ?? extraStr
        return r.isEmpty ? "resolved" : "resolved · resolution: \(r)"
    case "closed": return extraStr.isEmpty ? "closed" : "closed (\(extraStr))"
    case "activated": return "activated"
    case "edited": return "edited"
    case "confirmed", "bugconfirmed": return "confirmed the bug"
    case "commented": return "commented"
    default: return a.isEmpty ? "updated" : a
    }
}

/// Splits a ZenTao action comment into its attached-file names and the residual note. Reopen/resolve comments
/// often lead with `Added Files <name>\r\n<html>`; the file names go onto the activity row as chips and that
/// line is stripped from the note so it isn't repeated as prose.
func zentaoActionAttachments(_ comment: String) -> (files: [String], note: String) {
    let trimmed = String(comment.drop(while: { $0.isWhitespace }))
    let ns = trimmed as NSString
    guard let m = addedFilesRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) else {
        return ([], stripHtml(comment))
    }
    let names = ns.substring(with: m.range(at: 1)).split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    return (names, stripHtml(ns.substring(from: m.range.location + m.range.length)))
}

private let addedFilesRegex = try! NSRegularExpression(pattern: #"^Added Files\s+(.+?)(?:\r?\n|$)"#)

/// `assignedTo` is an account object (REST v1) or a bare string (legacy).
func accountName(_ value: Any?) -> String? {
    if isNull(value) { return nil }
    if let s = value as? String { return s.isEmpty ? nil : s }
    if let m = asMap(value) {
        let realname = m["realname"] as? String, account = m["account"] as? String
        let name = (realname?.isEmpty == false) ? realname : account
        return (name ?? "").isEmpty ? nil : name
    }
    return nil
}

/// The stable account handle (login) of a person reference - used for the assignee so it doesn't flip between
/// sync sources (the bug LIST returns `assignedTo` as a bare account string, DETAIL as `{account, realname}`).
func accountHandle(_ value: Any?) -> String? {
    if let s = value as? String { return s.isEmpty ? nil : s }
    if let m = asMap(value), let a = m["account"] as? String { return a }
    return nil
}

/// ZenTao files a closed task or bug under this pseudo-account: nobody.
let kZenTaoClosedAccount = "closed"

/// Who a ticket is assigned to (`accountHandle`); a closed ticket's `closed` pseudo-account is no one.
func assigneeHandle(_ value: Any?) -> String? {
    let handle = accountHandle(value)
    return handle == kZenTaoClosedAccount ? nil : handle
}

private func trimTrailingSlash(_ s: String) -> String { s.hasSuffix("/") ? String(s.dropLast()) : s }

/// Normalizes a typed ZenTao `ZenTaoEntity` into a unified `Ticket`.
func normalizeZenTao(_ e: ZenTaoEntity, type: ZenTaoType, accountId: String, baseUrl: String) -> Ticket {
    let id = e.idString
    // ZenTao sends titles HTML-escaped (`&quot;`).
    let title = decodeHtmlEntities(str(type == .task ? e.name : e.title) ?? "")
    let rawBody: String
    switch type {
    case .bug: rawBody = str(e.steps) ?? ""
    case .task: rawBody = str(e.desc ?? e.description) ?? ""
    case .story: rawBody = str(e.spec) ?? ""
    }
    let normalizedBase = trimTrailingSlash(baseUrl)
    // Kept as ZenTao's editor wrote it (HTML), and shown as HTML.
    let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawStatus = str(e.status) ?? ""
    let status = mapZenTaoStatus(type, rawStatus, confirmed: e.confirmed)

    // Labels: keywords (bug) + object type/category.
    var labels = (str(e.keywords) ?? "").split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    let resolution = (str(e.resolution) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if type == .bug && !resolution.isEmpty { labels.append("resolution:\(resolution)") }

    let scopeName = e.scopeName
    let projectId = "\(accountId):\(scopeName.isEmpty ? type.label : scopeName)"

    var entity: TicketProviderEntity?
    switch type {
    case .bug: entity = zentaoBugEntity(e, resolution: resolution, baseUrl: normalizedBase)
    case .task: entity = zentaoTaskEntity(e)
    case .story: entity = nil
    }
    return Ticket(
        id: zenTaoTicketId(accountId: accountId, type: type.rawValue, id: id),
        accountId: accountId, projectId: projectId, providerType: .zentao, externalKey: id,
        title: title, body: body, priority: mapZenTaoPriority(e.pri), status: status, providerStatus: rawStatus,
        sourceHash: contentHash(title, body), externalType: type.label, labels: labels,
        // Account handle (login), NOT realname: the bug LIST gives `assignedTo` as a bare account string but
        // DETAIL gives {account, realname}, so realname would differ between the card and the detail panel and
        // break the default "my tickets" filter, which matches against the account handle.
        assignee: assigneeHandle(e.assignedTo),
        url: "\(normalizedBase)/\(type.pathSegment)-view-\(id).html",
        severity: type == .bug ? e.severity : nil,
        createdAt: parseZenTaoDate(e.openedDate), updatedAt: parseZenTaoDate(e.lastEditedDate),
        providerEntity: entity)
}

/// A task's place in its family - its parent (a subtask) or its subtasks (a parent task) - and its hours.
private func zentaoTaskEntity(_ e: ZenTaoEntity) -> TicketProviderEntity {
    .zentaoTask(ZenTaoTaskEntity(
        parentId: (e.parent ?? 0) > 0 ? "\(e.parent!)" : nil,
        parentName: trimmedText(e.parentName),
        subtasks: e.children.filter { !$0.idString.isEmpty }.map { child in
            TicketSubtask(
                id: child.idString, title: decodeHtmlEntities(str(child.name) ?? ""),
                status: mapZenTaoStatus(.task, str(child.status) ?? ""), priority: child.pri,
                assignee: assigneeHandle(child.assignedTo) == nil ? nil : accountName(child.assignedTo))
        },
        execution: executionId(e.execution), project: executionId(e.project), module: trimmedText(e.module),
        isParent: e.isParent == 1 || e.parent == -1 || !e.children.isEmpty,
        estimate: e.estimate, consumed: e.consumed, left: e.left, realStarted: parseZenTaoDate(e.realStarted),
        openedByHandle: accountHandle(e.openedBy), taskType: trimmedText(e.type),
        executionName: trimmedText(e.executionName), story: executionId(e.story), storyTitle: trimmedText(e.storyTitle),
        fromBug: executionId(e.fromBug), estStarted: day(e.estStarted), deadline: day(e.deadline),
        openedBy: accountName(e.openedBy), openedDate: parseZenTaoDate(e.openedDate),
        finishedBy: accountName(e.finishedBy), finishedByHandle: accountHandle(e.finishedBy),
        finishedDate: parseZenTaoDate(e.finishedDate), closedBy: accountName(e.closedBy),
        closedDate: parseZenTaoDate(e.closedDate), lastEditedDate: parseZenTaoDate(e.lastEditedDate)))
}

private func zentaoBugEntity(_ e: ZenTaoEntity, resolution: String, baseUrl: String) -> TicketProviderEntity {
    .zentaoBug(ZenTaoBugEntity(
        product: trimmedText(e.product), project: trimmedText(e.project), execution: trimmedText(e.execution),
        branch: trimmedText(e.branch), module: trimmedText(e.module), story: trimmedText(e.story),
        task: trimmedText(e.task), plan: trimmedText(e.plan),
        productName: trimmedText(e.productName), projectName: trimmedText(e.projectName),
        executionName: trimmedText(e.executionName), storyTitle: trimmedText(e.storyTitle),
        taskName: trimmedText(e.taskName), planName: trimmedText(e.planName),
        bugType: trimmedText(e.type), os: trimmedText(e.os), browser: trimmedText(e.browser),
        confirmed: e.confirmed, severity: e.severity, activatedCount: e.activatedCount,
        resolution: resolution.isEmpty ? nil : resolution,
        openedBy: accountName(e.openedBy), openedByHandle: accountHandle(e.openedBy),
        openedDate: parseZenTaoDate(e.openedDate), openedBuild: formatZenTaoBuild(e.openedBuild),
        // Account handle, matching `Ticket.assignee` above.
        assignedTo: accountHandle(e.assignedTo), assignedDate: parseZenTaoDate(e.assignedDate),
        deadline: trimmedText(e.deadline),
        resolvedBy: accountName(e.resolvedBy), resolvedByHandle: accountHandle(e.resolvedBy),
        resolvedDate: parseZenTaoDate(e.resolvedDate), resolvedBuild: formatZenTaoBuild(e.resolvedBuild),
        closedBy: accountName(e.closedBy), closedDate: parseZenTaoDate(e.closedDate),
        lastEditedBy: accountName(e.lastEditedBy), lastEditedDate: parseZenTaoDate(e.lastEditedDate),
        attachments: zentaoAttachments(e, baseUrl: baseUrl)))
}

/// Maps ZenTao's id-keyed `files` map onto domain `TicketAttachment`s. Prefers the payload's absolute `url`;
/// falls back to the classic `{base}/file-download-{id}.{ext}` when it's missing. `webPath` becomes the
/// attachment's stream URL.
func zentaoAttachments(_ e: ZenTaoEntity, baseUrl: String) -> [TicketAttachment] {
    let base = trimTrailingSlash(baseUrl)
    var out: [TicketAttachment] = []
    for f in e.files {
        let id = str(f.id) ?? ""
        if id.isEmpty { continue }
        let ext = trimmedText(f.extension)?.lowercased()
        let title = trimmedText(f.title) ?? trimmedText(f.name) ?? (ext == nil ? "file-\(id)" : "file-\(id).\(ext!)")
        let url = trimmedText(f.url) ?? "\(base)/file-download-\(id)\(ext.map { ".\($0)" } ?? "")"
        let webPath = trimmedText(f.webPath)
        // Apache serves it with byte ranges; `file-download` streams the whole file through PHP, so a player
        // could only start once it all arrived.
        let stream = webPath.flatMap { p in URL(string: base).flatMap { URL(string: p, relativeTo: $0)?.absoluteURL.absoluteString } }
        out.append(TicketAttachment(
            id: id, title: title, url: url, extension: ext, size: f.size, addedBy: trimmedText(f.addedBy),
            addedDate: parseZenTaoDate(f.addedDate), streamUrl: stream))
    }
    return out
}

/// A task's execution id: given bare, or as `{id, name}` by some endpoints.
private func executionId(_ value: Any?) -> String? {
    if let m = asMap(value) { return executionId(m["id"]) }
    let id = trimmedText(value)
    return id == "0" ? nil : id
}

/// A date-only field (`2026-10-13`); nil for ZenTao's `0000-00-00` "none".
private func day(_ value: Any?) -> String? { parseZenTaoDate(value) == nil ? nil : zentaoDate(value) }

/// Formats ZenTao's `openedBuild`/`resolvedBuild`, which arrives as a build object (or list of them) like
/// `[{id: trunk, title: ...}]`. Renders each as `Trunk · title`; falls back to plain text.
func formatZenTaoBuild(_ value: Any?) -> String? {
    if isNull(value) { return nil }
    if let list = value as? [Any] {
        let parts = list.compactMap(buildLabel).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
    if let single = buildLabel(value), !single.isEmpty { return single }
    return trimmedText(value)
}

private func buildLabel(_ v: Any?) -> String? {
    if let m = asMap(v) {
        let id = (str(m["id"]) ?? "").trimmingCharacters(in: .whitespaces)
        let title = (str(m["title"]) ?? "").trimmingCharacters(in: .whitespaces)
        let idCap = id.isEmpty ? "" : id.prefix(1).uppercased() + id.dropFirst()
        return [idCap, title].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    return str(v)?.trimmingCharacters(in: .whitespaces)
}
