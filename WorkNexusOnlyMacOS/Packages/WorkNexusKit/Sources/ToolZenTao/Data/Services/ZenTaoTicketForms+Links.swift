import CoreDomain
import Foundation

// Ported from: lib/tools/zentao/data/models/{zentao_link_options,zentao_bug_from_task}.dart

/// Where a task sits - what a bug reported from it is filed under. Nil fields are unknown, and left to ZenTao.
struct TaskScope {
    var product: String?, project: String?, execution: String?, story: String?
}

/// The bug form's stories and tasks to link, which ZenTao 20+'s form page leaves for its own ajax calls, and
/// the scope of a bug reported from a task.
extension ZenTaoTicketForms {
    /// `options` with the stories and tasks to link filled in. ZenTao 20+'s form page leaves them out and loads
    /// them by ajax - the product's stories, and the execution's tasks once one is picked - so they are fetched
    /// the same way when the page did not have them. A list that cannot be loaded stays empty: the rest of the
    /// form is still usable.
    func withLinkOptions(_ options: BugFormOptions, productId: String, executionId: String) async -> BugFormOptions {
        let loadTasks = options.tasks.isEmpty && executionId != "0"
        async let storiesLoad: [FormOption] = options.stories.isEmpty && productId != "0"
            ? ajaxOptions("story-ajaxGetProductStories-\(productId)-0-0-0-false") : options.stories
        async let tasksLoad: [FormOption] = loadTasks ? ajaxOptions("task-ajaxGetExecutionTasks-\(executionId)") : options.tasks
        async let namesLoad: [String: String] = loadTasks ? taskNames(executionId) : [:]
        let (stories, tasks, names) = await (storiesLoad, tasksLoad, namesLoad)
        let people = Set(options.users.map(\.label))
        var out = options
        out.stories = stories.map { FormOption(value: $0.value, label: zentaoLinkLabel($0.label)) }
        out.tasks = tasks.map { FormOption(value: $0.value, label: zentaoTaskLabel($0, name: names[$0.value], people: people)) }
        return out
    }

    /// Execution `executionId`'s task names by id, subtasks included. The ajax list labels a finished task
    /// `id:finisher:name`, and a finisher outside the form's people cannot be told from a colon in the name, so
    /// the plain names come from the execution's task view. Empty when it cannot answer: labels then fall back
    /// to what the ajax list says.
    private func taskNames(_ executionId: String) async -> [String: String] {
        var names: [String: String] = [:]
        func add(_ task: ZenTaoEntity) {
            let name = zentaoText(task.name)
            if !task.idString.isEmpty, !name.isEmpty { names[task.idString] = name }
            task.children.forEach(add)
        }
        let limit = 500
        func page(_ p: Int) async throws -> ZenTaoExecutionTasksResponse {
            try await client.classicExecutionTasks(executionId, browseType: "all", recPerPage: limit, pageID: p)
        }
        do {
            let first = try await page(1)
            first.tasks.forEach(add)
            // The first page says how many there are, so the rest load at once (the form waits on them), up to 20 pages.
            let pages = min(max((first.total + limit - 1) / limit, 1), 20)
            if pages >= 2 {
                let rest = try await withThrowingTaskGroup(of: ZenTaoExecutionTasksResponse.self) { group -> [ZenTaoExecutionTasksResponse] in
                    for p in 2...pages { group.addTask { try await page(p) } }
                    var out: [ZenTaoExecutionTasksResponse] = []
                    for try await r in group { out.append(r) }
                    return out
                }
                rest.forEach { $0.tasks.forEach(add) }
            }
        } catch {
            // Keep what was read; the rest fall back to the ajax labels (a sign-in page is not JSON: likewise).
        }
        return names
    }

    private func ajaxOptions(_ path: String) async -> [FormOption] {
        do { return zentaoOptions(classicData(try await client.classicGet(path).data)) } catch { return [] }
    }

    func bugOptions(page p: JSON) -> BugFormOptions {
        // 20+ also nests some lists in its init `bug`.
        let bug = asMap(p["bug"]) ?? [:]
        func pick(_ key: String, _ alt: String? = nil) -> Any? {
            firstNonNull(p[key], alt.flatMap { p[$0] }, bug[key])
        }
        var o = BugFormOptions()
        o.products = zentaoOptions(pick("products"))
        o.branches = zentaoOptions(pick("branches", "branchTagOption"))
        o.modules = zentaoOptions(pick("moduleOptionMenu", "modules"))
        o.projects = zentaoOptions(pick("projects"))
        o.executions = zentaoOptions(pick("executions"))
        o.plans = zentaoOptions(pick("plans"))
        o.builds = zentaoOptions(pick("builds", "openedBuilds"))
        o.stories = zentaoOptions(pick("stories"))
        o.tasks = zentaoOptions(pick("tasks"))
        let assignable = zentaoOptions(pick("assignedToList", "productMembers"))
        o.users = assignable.isEmpty ? zentaoOptions(pick("users")) : assignable
        return o
    }

    // MARK: Bug from task

    /// Task `taskId`'s scope. ZenTao keeps no product on a task, so it is the execution's - or, when the
    /// execution spans several, the story's. When ZenTao cannot say, the scope is empty and the form opens as before.
    func taskScope(_ taskId: String, _ executionId: String?) async -> TaskScope {
        guard let task = await orNil({ try await client.entity("tasks", taskId) }) else {
            return TaskScope(product: nil, project: nil, execution: executionId, story: nil)
        }
        let execution = scopeId(task.execution) ?? executionId
        let story = scopeId(task.story)
        return TaskScope(product: await taskProduct(execution, story), project: scopeId(task.project),
                         execution: execution, story: story)
    }

    /// The product of a task in `execution` for `story`; nil when ZenTao cannot say. A failed lookup only loses
    /// the product, not the rest of the scope.
    private func taskProduct(_ execution: String?, _ story: String?) async -> String? {
        var products: [String] = []
        if let execution { products = await orNil({ try await client.executionProducts(execution) }) ?? [] }
        if products.count == 1 { return products[0] }
        var fromStory: String?
        if let story { fromStory = scopeId(await orNil({ try await client.entity("stories", story) })?.product) }
        return fromStory ?? products.first
    }

    private func scopeId(_ raw: Any?) -> String? {
        let id = zentaoId(raw)
        return id == "0" || id.isEmpty ? nil : id
    }

    /// `load`'s value, or nil when ZenTao cannot answer - a failed request, or a reply that is not JSON.
    private func orNil<T>(_ load: () async throws -> T) async -> T? {
        do { return try await load() } catch { return nil }
    }
}
