import CoreDomain
import Foundation
@testable import FeatureTicketEditor

/// An in-memory `ZenTaoTicketEditor`: records every call and answers from canned forms.
final class FakeEditor: ZenTaoTicketEditor, @unchecked Sendable {
    private let lock = NSLock()
    var bugForm = BugForm(draft: BugDraft(product: "7"), options: FakeEditor.bugOptions)
    var taskForm = TaskForm(draft: TaskDraft(execution: "5"), options: FakeEditor.taskOptions)
    var fetchedBugOptions: BugFormOptions?
    var fetchedTaskOptions: TaskFormOptions?
    var saveResult: Outcome<String> = .success("zt-a:bug:99")
    var formFailure: Failure?
    private(set) var calls: [String] = []
    private(set) var savedBugs: [BugDraft] = []
    private(set) var savedTasks: [TaskDraft] = []
    private(set) var newTaskParents: [String?] = []

    static var bugOptions: BugFormOptions {
        var o = BugFormOptions()
        o.products = [FormOption(value: "7", label: "WorkNexus"), FormOption(value: "8", label: "Other")]
        o.modules = [FormOption(value: "1", label: "/Feed")]
        o.executions = [FormOption(value: "5", label: "Sprint 5"), FormOption(value: "6", label: "Sprint 6")]
        o.builds = [FormOption(value: "trunk", label: "Trunk"), FormOption(value: "b1", label: "Build 1"), FormOption(value: "b2", label: "Build 2")]
        o.users = [FormOption(value: "thanh", label: "Thanh"), FormOption(value: "luci", label: "Luci")]
        o.stories = [FormOption(value: "12", label: "Autoplay story")]
        return o
    }
    static var taskOptions: TaskFormOptions {
        var o = TaskFormOptions()
        o.executions = [FormOption(value: "5", label: "Sprint 5"), FormOption(value: "6", label: "Sprint 6")]
        o.users = [FormOption(value: "thanh", label: "Thanh")]
        o.parents = [FormOption(value: "40", label: "Parent task")]
        return o
    }

    private func log(_ s: String) { lock.lock(); calls.append(s); lock.unlock() }

    func newBugForm(accountId: String, productId: String, copyOf: String?, executionId: String?, taskId: String?) async -> Outcome<BugForm> {
        log("newBugForm:\(productId)"); return formFailure.map { .failure($0) } ?? .success(bugForm)
    }
    func editBugForm(accountId: String, bugId: String) async -> Outcome<BugForm> {
        log("editBugForm:\(bugId)")
        var f = bugForm; f.draft.id = bugId; f.draft.title = "Existing"; return .success(f)
    }
    func bugOptions(accountId: String, productId: String, projectId: String, executionId: String) async -> Outcome<BugFormOptions> {
        log("bugOptions:\(productId):\(projectId):\(executionId)")
        return fetchedBugOptions.map { .success($0) } ?? .failure(.network("down"))
    }
    func bugModules(accountId: String, productId: String) async -> Outcome<[FormOption]> { .success([]) }
    func saveBug(accountId: String, form: BugForm, draft: BugDraft, uid: String) async -> Outcome<String> {
        lock.lock(); savedBugs.append(draft); lock.unlock(); return saveResult
    }
    func newTaskForm(accountId: String, executionId: String, parentId: String?, copyOf: String?, fromBug: String?) async -> Outcome<TaskForm> {
        lock.lock(); newTaskParents.append(parentId); lock.unlock()
        log("newTaskForm:\(executionId)")
        var f = taskForm; f.draft.execution = executionId == "0" ? f.draft.execution : executionId
        if let parentId { f.draft.parent = parentId }
        return .success(f)
    }
    func editTaskForm(accountId: String, taskId: String) async -> Outcome<TaskForm> {
        var f = taskForm; f.draft.id = taskId; f.draft.name = "Existing task"; return .success(f)
    }
    func taskOptions(accountId: String, executionId: String) async -> Outcome<TaskFormOptions> {
        log("taskOptions:\(executionId)")
        return fetchedTaskOptions.map { .success($0) } ?? .failure(.network("down"))
    }
    func saveTask(accountId: String, form: TaskForm, draft: TaskDraft, uid: String) async -> Outcome<String> {
        lock.lock(); savedTasks.append(draft); lock.unlock(); return saveResult
    }
    func loadImage(accountId: String, url: String) async -> Data? { nil }
    /// The upload id and file name of each image uploaded; names in `refusedUploads` are refused.
    private(set) var uploads: [String] = []
    var refusedUploads: Set<String> = []
    func uploadImage(accountId: String, uid: String, bytes: Data, fileName: String) async -> Outcome<String> {
        lock.lock(); uploads.append("\(uid):\(fileName)"); let n = uploads.count; lock.unlock()
        return refusedUploads.contains(fileName) ? .failure(.network("down")) : .success("/file-read-\(n).png")
    }
}

/// An in-memory draft repository.
final class FakeDrafts: ZenTaoTicketDraftRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: ZenTaoSavedDraft] = [:]
    private(set) var saves = 0
    var deleteFailure: Failure?

    init(_ initial: [ZenTaoSavedDraft] = []) { initial.forEach { items[$0.id] = $0 } }
    var all: [ZenTaoSavedDraft] { lock.lock(); defer { lock.unlock() }; return items.values.sorted { $0.updatedAt > $1.updatedAt } }

    func watchAll() -> AsyncStream<[ZenTaoSavedDraft]> { let v = all; return AsyncStream { $0.yield(v); $0.finish() } }
    func read(id: String) async -> Outcome<ZenTaoSavedDraft?> { lock.lock(); defer { lock.unlock() }; return .success(items[id]) }
    /// As the database does: a write from a cancelled task is refused. `saveFailures` more saves fail first.
    var saveFailures = 0
    func save(_ draft: ZenTaoSavedDraft) async -> Outcome<Void> {
        if Task.isCancelled { return .failure(.storage("cancelled")) }
        lock.lock(); defer { lock.unlock() }
        if saveFailures > 0 { saveFailures -= 1; return .failure(.storage("full")) }
        items[draft.id] = draft; saves += 1
        return .success(())
    }
    func delete(id: String) async -> Outcome<Void> {
        if let f = deleteFailure { return .failure(f) }
        lock.lock(); items[id] = nil; lock.unlock(); return .success(())
    }
}

final class FakeMembers: ZenTaoTeamMembers, @unchecked Sendable {
    func productMembers(accountId: String, productId: String) async -> Outcome<[ProviderUser]> { .success([]) }
    func executionMembers(accountId: String, executionId: String) async -> Outcome<[ProviderUser]> {
        .success([ProviderUser(account: "ryan", displayName: "Ryan")])
    }
}
