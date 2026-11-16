import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/bug_side_fields.dart
/// The bug's fields, as ZenTao's web form has them: where it belongs, what it affects, how bad it is, and who
/// handles it.
struct BugSideFields: View {
    let controller: BugEditorController
    let state: BugEditorState

    var body: some View {
        LocationSection(controller: controller, state: state)
        EditorSection(title: appString("editorSectionClassification", "Classification"), systemImage: "tag") {
            EditorField(label: appString("fieldType", "Type")) {
                OptionSelect(options: ZenTaoChoices.withValue(ZenTaoChoices.bugTypes, state.draft.type), value: state.draft.type) { v in controller.edit { $0.type = v } }
            }
            EditorField(label: appString("severity", "Severity")) {
                EditorLevelInput(level: .severity, value: state.draft.severity) { v in controller.edit { $0.severity = v } }
            }
            EditorField(label: appString("priority", "Priority")) {
                EditorLevelInput(level: .priority, value: state.draft.pri) { v in controller.edit { $0.pri = v } }
            }
            EditorField(label: appString("fieldOs", "OS")) {
                OptionMultiSelect(title: appString("fieldOs", "OS"), options: ZenTaoChoices.osList, values: state.draft.os) { v in controller.edit { $0.os = v } }
            }
            EditorField(label: appString("fieldBrowser", "Browser")) {
                OptionMultiSelect(title: appString("fieldBrowser", "Browser"), options: ZenTaoChoices.browserList, values: state.draft.browser) { v in controller.edit { $0.browser = v } }
            }
        }
        EditorSection(title: appString("editorSectionAssignment", "Assignment & schedule"), systemImage: "person.crop.circle") {
            EditorField(label: appString("fieldAssignTo", "Assign to")) {
                OptionSelect(options: state.form.options.users, value: state.draft.assignedTo, noneValue: "") { v in controller.edit { $0.assignedTo = v } }
            }
            EditorField(label: appString("fieldDeadline", "Deadline")) {
                EditorDateInput(value: state.draft.deadline) { v in controller.edit { $0.deadline = v } }
            }
        }
        MoreSection(controller: controller, state: state)
    }
}

/// Product, branch, module, project, execution, plan and affected builds.
private struct LocationSection: View {
    let controller: BugEditorController
    let state: BugEditorState

    var body: some View {
        let options = state.form.options, draft = state.draft
        EditorSection(title: appString("editorSectionLocation", "Location"), systemImage: "folder") {
            EditorField(label: appString("fieldProduct", "Product"), required: true, missing: state.missing.contains(.product)) {
                OptionSelect(options: options.products, value: draft.product) { v in Task { await controller.changeScope(product: v) } }
            }
            if !options.branches.isEmpty {
                EditorField(label: appString("fieldBranch", "Branch")) {
                    OptionSelect(options: options.branches, value: draft.branch, noneValue: "0") { v in controller.edit { $0.branch = v } }
                }
            }
            EditorField(label: appString("fieldModule", "Module")) {
                OptionSelect(options: options.modules, value: draft.module, noneValue: "0") { v in controller.edit { $0.module = v } }
            }
            EditorField(label: appString("project", "Project")) {
                OptionSelect(options: options.projects, value: draft.project, noneValue: "0") { v in Task { await controller.changeScope(project: v) } }
            }
            EditorField(label: appString("fieldExecution", "Execution")) {
                OptionSelect(options: options.executions, value: draft.execution, noneValue: "0") { v in Task { await controller.changeScope(execution: v) } }
            }
            if !options.plans.isEmpty {
                EditorField(label: appString("fieldPlan", "Plan")) {
                    OptionSelect(options: options.plans, value: draft.plan, noneValue: "0") { v in controller.edit { $0.plan = v } }
                }
            }
            EditorField(label: appString("fieldAffectedBuilds", "Affected builds"), required: true, missing: state.missing.contains(.openedBuilds)) {
                OptionMultiSelect(title: appString("fieldAffectedBuilds", "Affected builds"), options: options.builds, values: draft.openedBuilds) { v in controller.edit { $0.openedBuilds = v } }
            }
        }
    }
}

/// Story, task, notify list, keywords and colour.
private struct MoreSection: View {
    let controller: BugEditorController
    let state: BugEditorState

    var body: some View {
        let options = state.form.options, draft = state.draft
        EditorSection(title: appString("editorSectionMore", "More"), systemImage: "ellipsis.circle") {
            EditorField(label: appString("fieldStory", "Story")) {
                OptionSelect(options: options.stories, value: draft.story, noneValue: "0") { v in controller.edit { $0.story = v } }
            }
            EditorField(label: appString("fieldTask", "Task")) {
                BugTaskSelect(options: options, execution: draft.execution, task: draft.task,
                              onExecution: { v in Task { await controller.changeScope(execution: v) } },
                              onTask: { v in controller.edit { $0.task = v } })
            }
            EditorField(label: appString("fieldMailto", "Notify")) {
                OptionMultiSelect(title: appString("fieldMailto", "Notify"), options: options.users, values: draft.mailto) { v in controller.edit { $0.mailto = v } }
            }
            EditorField(label: appString("fieldKeywords", "Keywords")) {
                EditorTextInput(initial: draft.keywords) { v in controller.edit { $0.keywords = v } }
            }
            EditorField(label: appString("fieldColor", "Colour")) {
                TitleColorInput(value: draft.color) { v in controller.edit { $0.color = v } }
            }
        }
    }
}
