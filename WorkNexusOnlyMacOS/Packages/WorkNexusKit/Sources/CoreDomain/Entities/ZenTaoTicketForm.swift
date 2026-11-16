import Foundation

/// Ported from: lib/core/domain/entities/zentao_ticket_form.dart
/// One choice in a form's select: the value ZenTao stores and its label.
public struct FormOption: Hashable, Sendable {
    public var value: String
    public var label: String
    public init(value: String, label: String) { self.value = value; self.label = label }
}

/// A ZenTao bug as edited in the form (every field ZenTao's web form has). Ids are ZenTao's, as strings; "0" means none.
public struct BugDraft: Hashable, Sendable {
    public var id: String?
    public var product: String
    public var branch = "0"
    public var module = "0"
    public var project = "0"
    public var execution = "0"
    public var plan = "0"
    public var openedBuilds: [String] = ["trunk"]
    public var assignedTo = ""
    public var deadline = ""
    public var type = "codeerror"
    public var os: [String] = []
    public var browser: [String] = []
    public var title = ""
    public var color = ""
    public var severity = 3
    public var pri = 3
    public var steps = ""
    public var story = "0"
    public var task = "0"
    public var mailto: [String] = []
    public var keywords = ""
    public var files: [TicketAttachment] = []
    public var newFiles: [DraftFile] = []
    public init(id: String? = nil, product: String) { self.id = id; self.product = product }
}

/// The choices a bug form offers, as ZenTao lists them for the bug's product (and project / execution).
public struct BugFormOptions: Hashable, Sendable {
    public var products: [FormOption] = []
    public var branches: [FormOption] = []
    public var modules: [FormOption] = []
    public var projects: [FormOption] = []
    public var executions: [FormOption] = []
    public var plans: [FormOption] = []
    public var builds: [FormOption] = []
    public var stories: [FormOption] = []
    public var tasks: [FormOption] = []
    public var users: [FormOption] = []
    public init() {}
}

/// A bug form as loaded: the bug, its choices, and what must be sent back unchanged (`kept`).
public struct BugForm: Hashable, Sendable {
    public var draft: BugDraft
    public var options: BugFormOptions
    public var kept: [String: String]
    public init(draft: BugDraft, options: BugFormOptions, kept: [String: String] = [:]) {
        self.draft = draft; self.options = options; self.kept = kept
    }
}

/// A ZenTao task as edited in the form (every field ZenTao's web form has).
public struct TaskDraft: Hashable, Sendable {
    public var id: String?
    public var execution: String
    public var module = "0"
    public var story = "0"
    public var parent = "0"
    public var name = ""
    public var type = "devel"
    public var pri = 3
    public var estimate: Double = 0
    public var left: Double = 0
    public var consumed: Double = 0
    public var status = "wait"
    public var assignedTo = ""
    public var estStarted = ""
    public var deadline = ""
    public var desc = ""
    public var color = ""
    public var mailto: [String] = []
    public var keywords = ""
    public var files: [TicketAttachment] = []
    public var newFiles: [DraftFile] = []
    public init(id: String? = nil, execution: String) { self.id = id; self.execution = execution }
}

/// The choices a task form offers, as ZenTao lists them for its execution.
public struct TaskFormOptions: Hashable, Sendable {
    public var executions: [FormOption] = []
    public var modules: [FormOption] = []
    public var stories: [FormOption] = []
    public var parents: [FormOption] = []
    public var users: [FormOption] = []
    public init() {}
}

/// A task form as loaded: the task, its choices, and the fields to send back unchanged (`kept`).
public struct TaskForm: Hashable, Sendable {
    public var draft: TaskDraft
    public var options: TaskFormOptions
    public var kept: [String: String]
    public init(draft: TaskDraft, options: TaskFormOptions, kept: [String: String] = [:]) {
        self.draft = draft; self.options = options; self.kept = kept
    }
}
