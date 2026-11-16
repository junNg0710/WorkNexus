/// Ported from: the detail hooks of lib/tools/zentao/zentao_module.dart
import CoreDomain
import SwiftUI

/// What `ZentaoModule` answers the detail panel's `ToolModule.build*` hooks with. Each returns nil when it has nothing
/// to show (a story offers Assign only; a task without hours has no effort bar).
@MainActor
public struct ZentaoDetailHooks {
    let deps: ZentaoDependencies; let state: ZentaoUIState
    public init(deps: ZentaoDependencies, state: ZentaoUIState) { self.deps = deps; self.state = state }

    /// ZenTao's toolbar: Assign, the main status action and a "⋯" menu.
    public func actions(_ t: Ticket) -> AnyView? { AnyView(ZentaoTicketActions(deps: deps, state: state, ticket: t)) }

    /// A subtask's link to its parent.
    public func headerExtras(_ t: Ticket) -> AnyView? {
        if case .zentaoTask(let task) = t.providerEntity, let parent = task.parentId {
            return AnyView(ZentaoParentTaskLink(deps: deps, ticket: t, parentId: parent, parentName: task.parentName))
        }
        return nil
    }

    /// A bug's real status ("Resolved · Fixed").
    public func statusStrip(_ t: Ticket) -> AnyView? {
        if case .zentaoBug(let bug) = t.providerEntity { return AnyView(ZentaoBugStatusStrip(ticket: t, bug: bug)) }
        return nil
    }

    public func effort(_ t: Ticket) -> AnyView? {
        if case .zentaoTask(let task) = t.providerEntity { return AnyView(ZentaoTaskEffortBar(task: task)) }
        return nil
    }

    public func subtasks(_ t: Ticket) -> AnyView? {
        if case .zentaoTask(let task) = t.providerEntity, !task.subtasks.isEmpty {
            return AnyView(ZentaoSubtaskList(deps: deps, ticket: t, subtasks: task.subtasks))
        }
        return nil
    }

    public func attachments(_ t: Ticket) -> AnyView? {
        if case .zentaoBug(let bug) = t.providerEntity, !bug.attachments.isEmpty {
            return AnyView(ZentaoBugAttachments(deps: deps, ticket: t, attachments: bug.attachments))
        }
        return nil
    }

    public func sidebar(_ t: Ticket) -> AnyView? {
        switch t.providerEntity {
        case .zentaoBug(let bug): AnyView(ZentaoBugSections(deps: deps, state: state, bug: bug, ticket: t))
        case .zentaoTask(let task): AnyView(ZentaoTaskSections(deps: deps, state: state, task: task, ticket: t))
        default: nil
        }
    }
}
