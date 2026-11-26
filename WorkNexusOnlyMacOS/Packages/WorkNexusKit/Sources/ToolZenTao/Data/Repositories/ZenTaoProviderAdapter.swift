import CoreDomain
import Foundation

/// What `ZenTaoProviderAdapter.listTaskBugs` read: the bugs, and how far they cover the execution's bug list -
/// all of it (`complete`), or the bugs of every task above `above`; neither when ZenTao did not sort them by task.
public struct ZenTaoTaskBugsRead: Sendable {
    public var bugs: [Ticket]
    public var complete: Bool
    public var above: Int?
}

/// Ported from: lib/tools/zentao/data/repositories/zentao_adapter.dart
/// ZenTao implementation of `ProviderAdapter`, bound to one account. The paging/list methods live in
/// `ZenTaoProviderAdapter+Lists.swift`, the write actions in `ZenTaoProviderAdapter+Actions.swift`.
public final class ZenTaoProviderAdapter: ZenTaoMessagesAdapter, @unchecked Sendable {
    public let accountId: String
    public let client: ZenTaoClient
    let lists: ZenTaoSourceLists

    let lock = NSLock()
    private var detailMemo: [String: (serial: Int, task: Task<ZenTaoEntity, Error>)] = [:]
    /// Login -> numeric user id, read once from `GET /users` (the person pages take the id).
    var userIds: [String: String] = [:]
    /// Login as typed (lowercased) -> the login as ZenTao writes it ("junng" -> "JunNg").
    var userLogins: [String: String] = [:]
    var userIdsLoaded = false
    private var serial = 0

    public init(accountId: String, client: ZenTaoClient) {
        self.accountId = accountId
        self.client = client
        self.lists = ZenTaoSourceLists(client: client, accountId: accountId)
    }

    public var providerType: ProviderType { .zentao }

    public func fetchBytes(url: String, projectPath: String?, projectId: String?) async -> Data? { try? await client.fetchBytes(url) }
    public func downloadBytes(url: String) async -> Data? { try? await client.downloadBytes(url) }
    public func streamRequest(url: String) async -> MediaRequest? { try? await client.streamRequest(url) }

    public func testConnection() async -> Outcome<ConnectionCheck> {
        await zenGuard {
            let baseUrl = try await client.detectBaseUrl()
            let account = try await client.authenticate()
            return ConnectionCheck(ok: true, account: account, baseUrl: baseUrl)
        }
    }

    // MARK: Assigned tickets

    public func listAssignedTickets(sinceCursor: String?) async -> Outcome<TicketPage> {
        await zenGuard {
            // REST v1 "assigned to me" per type. Each `/user` group is paginated and reports a `total`, so we
            // page through it - otherwise only the first (most-recent) page comes back and older items are
            // silently dropped. Bugs and tasks page independently, so they are fetched side by side.
            async let bugs = fetchAssigned("bug", .bug)
            async let tasks = fetchAssigned("task", .task)
            let tickets = try await bugs + tasks
            // Incremental cursor: max updatedAt seen, filtered client-side.
            let cursor = sinceCursor.flatMap(ZenTaoDayParser.parse)
            let filtered = cursor == nil ? tickets : tickets.filter { t in t.updatedAt.map { $0 > cursor! } ?? true }
            return TicketPage(tickets: filtered, nextCursor: tickets.compactMap(\.updatedAt).max().map(ZenTaoDayParser.iso8601))
        }
    }

    /// Fetches every "assigned to me" item of one `type`, paging through `GET /user?type=assignedTo&fields=<field>`
    /// until the reported `total` is reached. A seen-set dedupes by id, which both prevents duplicates and safely
    /// stops a server that ignores the `page` parameter (a page that adds nothing new ends the loop).
    private func fetchAssigned(_ field: String, _ type: ZenTaoType) async throws -> [Ticket] {
        let limit = ZenTaoSourceLists.pageLimit
        var out: [Ticket] = []
        var seen = Set<String>()
        var total = 0
        for page in 1...50 {
            let res = try await client.assigned(type: "assignedTo", fields: field, page: page, limit: limit)
            guard let group = res.group(for: field), !group.items.isEmpty else { break }
            if group.total > 0 { total = group.total }
            var added = 0
            for entity in group.items {
                let id = entity.idString
                if !id.isEmpty && !seen.insert(id).inserted { continue }     // already have it
                out.append(normalizeZenTao(entity, type: type, accountId: accountId, baseUrl: client.baseUrl))
                added += 1
            }
            if added == 0 { break }                                          // server ignored `page` - stop
            if total > 0 && out.count >= total { break }
        }
        return out
    }

    // MARK: Detail, comments, activity

    public func getTicket(_ ticket: Ticket) async -> Outcome<Ticket> {
        await zenGuard {
            lock.withLock { _ = detailMemo.removeValue(forKey: "\(ticket.externalType ?? ""):\(ticket.externalKey)") }
            let entity = try await fetchDetail(ticket)
            return normalizeZenTao(entity, type: zenTaoType(of: ticket), accountId: accountId, baseUrl: client.baseUrl)
        }
    }

    public func listComments(_ ticket: Ticket) async -> Outcome<[Comment]> {
        await zenGuard {
            let entity = try await fetchDetail(ticket)
            var comments: [Comment] = []
            for a in entity.actions {
                // Only pure comments are bubbles; notes attached to a state change (e.g. "activated" + a
                // message) are shown inline on the activity row.
                let body = zentaoCommentBody(a, baseUrl: client.baseUrl)        // HTML, as written in ZenTao's editor, and its files
                guard a.actionType == "commented", !body.isEmpty else { continue }
                comments.append(Comment(
                    id: "\(ticket.id):\(str(a.id) ?? "\(comments.count)")", ticketId: ticket.id,
                    authorName: accountName(a.actor) ?? "unknown", body: body,
                    createdAt: parseZenTaoDate(a.date) ?? Date()))
            }
            return comments
        }
    }

    public func postComment(_ ticket: Ticket, body: String) async -> Outcome<Comment> {
        await zenGuard {
            var form = ZenTaoForm()
            form.put("comment", body)
            _ = try await client.classicActionPost("action-comment-\(zenTaoType(of: ticket).pathSegment)-\(ticket.externalKey)", form)
            return Comment(id: "\(ticket.id):\(Int(Date().timeIntervalSince1970 * 1_000_000))", ticketId: ticket.id,
                           authorName: "You", body: body, createdAt: Date())
        }
    }

    public func listActivity(_ ticket: Ticket) async -> Outcome<[ActivityEvent]> {
        await zenGuard {
            let entity = try await fetchDetail(ticket)
            var events: [ActivityEvent] = []
            for a in entity.actions {
                // Pure comments render as bubbles, not activity rows.
                if a.actionType == "commented" { continue }
                let parsed = zentaoActionAttachments(a.commentText)
                events.append(ActivityEvent(
                    id: "\(ticket.id):\(str(a.id) ?? "\(events.count)")", ticketId: ticket.id,
                    actor: accountName(a.actor) ?? "unknown", action: zentaoActionText(a),
                    at: parseZenTaoDate(a.date) ?? Date(), detail: parsed.note.isEmpty ? nil : parsed.note,
                    attachments: zentaoActivityFileNames(a, noted: parsed.files, baseUrl: client.baseUrl)))
            }
            return events
        }
    }

    // MARK: Users, containers

    public func listUsers() async -> Outcome<[ProviderUser]> {
        await zenGuard {
            let res = try await client.users(limit: 1000)
            let users = res.users.compactMap { u -> ProviderUser? in
                let account = u.account ?? ""
                if account.isEmpty { return nil }
                return ProviderUser(account: account, displayName: (u.realname ?? "").isEmpty ? account : u.realname!)
            }
            return users.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        }
    }

    public func listProducts() async -> Outcome<[ProviderProduct]> { await zenGuard { try await lists.products() } }
    public func listProjects() async -> Outcome<[ProviderProject]> { await zenGuard { try await lists.projects() } }

    public func listProjectExecutions(projectId: String) async -> Outcome<[ProviderExecution]> {
        await zenGuard {
            var out: [ProviderExecution] = []
            var seen = Set<String>()
            var total = 0
            for page in 1...50 {
                let res = try await client.projectExecutions(projectId, page: page, limit: ZenTaoSourceLists.pageLimit)
                if res.total > 0 { total = res.total }
                var added = 0
                for e in res.executions where !e.id.isEmpty && seen.insert(e.id).inserted {
                    out.append(ProviderExecution(id: e.id, name: e.name.isEmpty ? e.id : e.name, projectId: projectId, accountId: accountId))
                    added += 1
                }
                if added == 0 { break }
                if total > 0 && out.count >= total { break }
            }
            return out
        }
    }

    // MARK: Messages / user info (ZenTaoMessagesAdapter)

    public func fetchMessages() async -> Outcome<ZenTaoRawReply> { await zenGuard { ZenTaoRawReply(try await client.messages()) } }

    public func messageAction(_ action: String) async -> Outcome<Void> { await zenGuard { try await client.messageAction(action) } }

    public func fetchUserInfo(fields: String, limit: Int) async -> Outcome<ZenTaoRawReply> {
        let res = await zenGuard { try await client.userInfo(fields: fields, limit: limit) }
        // The client lets 4xx through as data; an error body has no profile.
        if case .success(let value) = res, asMap(value["profile"]) == nil {
            let error = str(firstNonNull(value["error"], value["message"])) ?? "no profile"
            return .failure(.auth("ZenTao user info unavailable: \(error)"))
        }
        return res.map(ZenTaoRawReply.init)
    }

    // MARK: Detail memo

    /// Fetches a ticket's full detail (with its embedded `actions`), preferring REST v1 and falling back to the
    /// classic `{type}-view-{id}.json` endpoint when v1 returns an empty body. Opening a ticket asks for its
    /// detail, comments and activity in turn, and all three come from the same reply - the memo keeps that to one
    /// request. It is dropped four seconds after completion, so later syncs fetch fresh data.
    func fetchDetail(_ ticket: Ticket) async throws -> ZenTaoEntity {
        let key = "\(ticket.externalType ?? ""):\(ticket.externalKey)"
        let task: Task<ZenTaoEntity, Error> = lock.withLock {
            if let hit = detailMemo[key] { return hit.task }
            serial += 1
            let mine = serial
            let t = Task { try await self.loadDetail(ticket) }
            detailMemo[key] = (mine, t)
            Task {
                _ = await t.result
                if case .failure = await t.result { self.dropMemo(key, mine) } else {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    self.dropMemo(key, mine)
                }
            }
            return t
        }
        return try await task.value
    }

    private func dropMemo(_ key: String, _ serial: Int) {
        lock.withLock { if detailMemo[key]?.serial == serial { detailMemo[key] = nil } }
    }

    private func loadDetail(_ ticket: Ticket) async throws -> ZenTaoEntity {
        let t = zenTaoType(of: ticket)
        let entity = try await client.entity(t.plural, ticket.externalKey)
        if !entity.idString.isEmpty { return entity }
        let fallback = try await client.classicViewJson(t.pathSegment, ticket.externalKey)
        return fallback.map(ZenTaoEntity.init(json:)) ?? entity
    }
}

/// `_typeOf`: the ZenTao kind a ticket is (`Task` / `Story`, else a bug).
func zenTaoType(of ticket: Ticket) -> ZenTaoType {
    switch ticket.externalType { case "Task": .task; case "Story": .story; default: .bug }
}
