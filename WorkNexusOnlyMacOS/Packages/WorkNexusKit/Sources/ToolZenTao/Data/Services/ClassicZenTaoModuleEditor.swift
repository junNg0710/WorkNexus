/// Not in the Flutter app.
import CoreDomain
import Foundation

/// `ZenTaoModuleEditor` over ZenTao's own module page (`tree-manageChild`), on each account's pooled client.
public struct ClassicZenTaoModuleEditor: ZenTaoModuleEditor {
    private let clients: ZenTaoClientProvider
    public init(clients: ZenTaoClientProvider) { self.clients = clients }

    public func addModule(accountId: String, rootId: String, bugs: Bool, name: String, parentId: String?) async -> Outcome<[FormOption]> {
        guard let client = await clients.zenTaoClient(accountId: accountId) else { return .failure(.auth("ZenTao account is not signed in")) }
        do {
            return .success(try await ZenTaoTicketForms(client: client).addModule(rootId: rootId, bugs: bugs, name: name, parentId: parentId))
        } catch let f as Failure { return .failure(f) }
        catch let e as ZenTaoError {
            if case .format = e { return .failure(.parse("ZenTao sent an unreadable reply")) }
            return .failure(.network(e.message.isEmpty ? "ZenTao request failed" : e.message))
        } catch { return .failure(.parse("ZenTao sent an unreadable reply")) }
    }
}

extension ZenTaoTicketForms {
    /// The modules a board lists: product `rootId`'s on its bug form (`bugs`), else execution `rootId`'s on its task form.
    func boardModules(rootId: String, bugs: Bool) async throws -> [FormOption] {
        bugs ? try await bugModules(rootId) : try await taskOptions(rootId).modules
    }

    /// Adds module `name` under `parentId` (nil: at the top) the way ZenTao's module page does, and returns the module
    /// list read back afterwards.
    ///
    /// The page posts every row of its form, old and new; ZenTao creates the rows it is sent without an id and leaves
    /// alone the modules it is not sent, so only the new one goes. What ZenTao answers differs by version (18.x prints
    /// a script, 20+ JSON), so success is told by the list itself: the module has to be in it afterwards.
    func addModule(rootId: String, bugs: Bool, name: String, parentId: String?) async throws -> [FormOption] {
        let parent = parentId ?? "0"
        let before = Set(try await boardModules(rootId: rootId, bugs: bugs).map(\.value))
        var form = ZenTaoForm()
        form.put("parentModuleID", parent)
        // New modules go after the ones there (ZenTao orders them from this).
        form.put("maxOrder", "\(await lastOrder(rootId: rootId, bugs: bugs, parent: parent))")
        form.put("modules[]", list: [name])
        form.put("shorts[]", list: [""])
        form.put("branch[]", list: ["0"])
        let reply = try await client.classicActionPost("tree-manageChild-\(rootId)-\(bugs ? "bug" : "task")", form)
        if let refused = Self.refusal(reply.data) { throw Failure.validation(refused) }
        let after = try await boardModules(rootId: rootId, bugs: bugs)
        let wanted = name.lowercased()
        let added = after.contains { !before.contains($0.value) && Self.lastPart($0.label) == wanted }
        guard added else {
            throw Failure.validation("ZenTao did not add the module. Your account may not be allowed to manage modules.")
        }
        return after
    }

    /// The highest order among `parent`'s modules, from the module page; 0 when it cannot be read (the new module
    /// then sorts among the first, which is harmless).
    private func lastOrder(rootId: String, bugs: Bool, parent: String) async -> Int {
        let path = bugs ? "tree-browse-\(rootId)-bug-\(parent)" : "tree-browsetask-\(rootId)-0-\(parent)"
        guard let view = try? await page(path) else { return 0 }
        return listOrMapValues(view["sons"]).compactMap { zentaoInt(asMap($0)?["order"]) }.max() ?? 0
    }

    /// What ZenTao said when it refused the form, or nil when it did not say it refused.
    static func refusal(_ body: Any?) -> String? {
        guard let reply = classicPayload(body), str(reply["result"]) == "fail" || str(reply["status"]) == "fail" else { return nil }
        func text(_ v: Any) -> String {
            if let list = v as? [Any] { return list.map { zentaoText($0) }.joined(separator: " ") }
            return zentaoText(v)
        }
        if let entries = asEntries(reply["message"]) { return entries.map { text($0.value) }.joined(separator: "\n") }
        if let list = reply["message"] as? [Any] { return list.map(text).joined(separator: "\n") }
        let message = zentaoText(reply["message"])
        return message.isEmpty ? "ZenTao refused the module" : message
    }

    /// The module's own name in a path ("/Live stream/Share" -> "share"), as names are compared.
    static func lastPart(_ path: String) -> String {
        (path.split(separator: "/").last.map(String.init) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }
}
