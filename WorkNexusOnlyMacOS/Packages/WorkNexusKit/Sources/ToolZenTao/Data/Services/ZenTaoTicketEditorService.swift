import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/data/services/zentao_ticket_editor_service.dart
/// `ZenTaoTicketEditor` over each account's pooled ZenTao client; a saved bug or task is fetched back and
/// stored, so the board and detail show it.
public struct ZenTaoTicketEditorService: ZenTaoTicketEditor {
    private let clients: ZenTaoClientProvider
    private let tickets: ZenTaoTicketService

    public init(clients: ZenTaoClientProvider, tickets: ZenTaoTicketService) { self.clients = clients; self.tickets = tickets }

    private func run<T>(_ accountId: String, _ body: (ZenTaoTicketForms) async throws -> T) async -> Outcome<T> {
        guard let client = await clients.zenTaoClient(accountId: accountId) else { return .failure(.auth("ZenTao account is not signed in")) }
        do { return .success(try await body(ZenTaoTicketForms(client: client))) }
        catch let f as Failure { return .failure(f) }
        catch let e as ZenTaoError {
            if case .format = e { return .failure(.parse("ZenTao sent an unreadable form")) }
            return .failure(.network(e.message.isEmpty ? "ZenTao request failed" : e.message))
        } catch { return .failure(.parse("ZenTao sent an unreadable form")) }
    }

    /// Stores ZenTao `type` `id` (just saved) and returns its ticket id.
    private func store(_ accountId: String, _ type: String, _ id: String) async -> Outcome<String> {
        let client = await clients.zenTaoClient(accountId: accountId)
        let host = client.flatMap { URL(string: $0.baseUrl)?.host } ?? ""
        return await tickets.fetchZenTaoTicket(host: host, type: type, id: id)
    }

    public func newBugForm(accountId: String, productId: String, copyOf: String?, executionId: String?, taskId: String?) async -> Outcome<BugForm> {
        await run(accountId) { try await $0.newBug(productId, copyOf: copyOf, executionId: executionId, taskId: taskId) }
    }

    public func editBugForm(accountId: String, bugId: String) async -> Outcome<BugForm> {
        await run(accountId) { try await $0.editBug(bugId) }
    }

    public func bugOptions(accountId: String, productId: String, projectId: String, executionId: String) async -> Outcome<BugFormOptions> {
        await run(accountId) { try await $0.bugOptions(productId, projectId: projectId, executionId: executionId) }
    }

    public func bugModules(accountId: String, productId: String) async -> Outcome<[FormOption]> {
        await run(accountId) { try await $0.bugModules(productId) }
    }

    public func saveBug(accountId: String, form: BugForm, draft: BugDraft, uid: String) async -> Outcome<String> {
        switch await run(accountId, { try await $0.saveBug(form, draft, uid: uid) }) {
        case .success(let id): return await store(accountId, "bug", id)
        case .failure(let f): return .failure(f)
        }
    }

    public func newTaskForm(accountId: String, executionId: String, parentId: String?, copyOf: String?, fromBug: String?) async -> Outcome<TaskForm> {
        await run(accountId) { try await $0.newTask(executionId, parentId: parentId, copyOf: copyOf, fromBug: fromBug) }
    }

    public func editTaskForm(accountId: String, taskId: String) async -> Outcome<TaskForm> {
        await run(accountId) { try await $0.editTask(taskId) }
    }

    public func taskOptions(accountId: String, executionId: String) async -> Outcome<TaskFormOptions> {
        await run(accountId) { try await $0.taskOptions(executionId) }
    }

    public func saveTask(accountId: String, form: TaskForm, draft: TaskDraft, uid: String) async -> Outcome<String> {
        switch await run(accountId, { try await $0.saveTask(form, draft, uid: uid) }) {
        case .success(let id): return await store(accountId, "task", id)
        case .failure(let f): return .failure(f)
        }
    }

    public func loadImage(accountId: String, url: String) async -> Data? {
        guard let client = await clients.zenTaoClient(accountId: accountId) else { return nil }
        return (try? await client.fetchBytes(url)) ?? nil
    }

    public func uploadImage(accountId: String, uid: String, bytes: Data, fileName: String) async -> Outcome<String> {
        await run(accountId) { try await $0.uploadImage(uid: uid, bytes: bytes, name: fileName) }
    }
}

/// Ported from: lib/tools/zentao/data/repositories/classic_zentao_team_members.dart
/// `ZenTaoTeamMembers` read from ZenTao's new bug and new task forms over each account's pooled client.
public struct ClassicZenTaoTeamMembers: ZenTaoTeamMembers {
    private let clients: ZenTaoClientProvider
    public init(clients: ZenTaoClientProvider) { self.clients = clients }

    public func productMembers(accountId: String, productId: String) async -> Outcome<[ProviderUser]> {
        await run(accountId) { try await $0.productMembers(productId) }
    }

    public func executionMembers(accountId: String, executionId: String) async -> Outcome<[ProviderUser]> {
        await run(accountId) { try await $0.executionMembers(executionId) }
    }

    /// The initial ZenTao puts before each name in its member lists (`T:Thanh`) to sort them; a bug names its
    /// opener and resolver without it.
    private static let initial = #"^\p{L}:"#

    private func run(_ accountId: String, _ read: (ZenTaoTicketForms) async throws -> [FormOption]) async -> Outcome<[ProviderUser]> {
        guard let client = await clients.zenTaoClient(accountId: accountId) else { return .failure(.auth("ZenTao account is not signed in")) }
        do {
            let options = try await read(ZenTaoTicketForms(client: client))
            return .success(options.map {
                ProviderUser(account: $0.value, displayName: $0.label.replacingRegex(Self.initial, with: ""))
            })
        } catch let f as Failure { return .failure(f) }
        catch let e as ZenTaoError {
            if case .format = e { return .failure(.parse("ZenTao sent an unreadable form")) }
            return .failure(.network(e.message.isEmpty ? "ZenTao request failed" : e.message))
        } catch { return .failure(.parse("ZenTao sent an unreadable form")) }
    }
}
