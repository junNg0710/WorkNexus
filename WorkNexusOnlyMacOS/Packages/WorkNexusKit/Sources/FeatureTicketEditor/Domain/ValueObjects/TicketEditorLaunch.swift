import CoreDomain
import Foundation

/// Ported from: lib/core/navigation/ticket_editor_route.dart
/// Which ZenTao bug or task the editor is open on, with everything the Flutter `TicketEditorRoute` subclasses carry
/// (the Swift `TicketEditorRoute` in CoreTools only has the four plain cases). `newBug`: product `productId` ("0":
/// the one ZenTao has current), starting as a copy of `copyOf`, or filed against `executionId` and `taskId`, or as
/// kept draft `draftId`. `newTask`: execution `executionId`, a subtask of `parentId`, a copy of `copyOf`, made from
/// bug `fromBug`, or kept draft `draftId`.
public enum TicketEditorLaunch: Hashable, Sendable {
    case newBug(accountId: String, productId: String = "0", copyOf: String? = nil, executionId: String? = nil,
                taskId: String? = nil, draftId: String? = nil)
    case newTask(accountId: String, executionId: String = "0", parentId: String? = nil, draftId: String? = nil,
                 copyOf: String? = nil, fromBug: String? = nil)
    case editBug(accountId: String, bugId: String)
    case editTask(accountId: String, taskId: String)

    public var accountId: String {
        switch self {
        case .newBug(let a, _, _, _, _, _), .newTask(let a, _, _, _, _, _), .editBug(let a, _), .editTask(let a, _): a
        }
    }
    public var isBug: Bool {
        switch self { case .newBug, .editBug: true; case .newTask, .editTask: false }
    }
    public var isNew: Bool {
        switch self { case .newBug, .newTask: true; case .editBug, .editTask: false }
    }
    public var draftId: String? {
        switch self {
        case .newBug(_, _, _, _, _, let d), .newTask(_, _, _, let d, _, _): d
        default: nil
        }
    }

    /// The launch that picks kept `draft` up again (`draftRoute` in ticket_draft_labels.dart).
    public static func resuming(_ draft: ZenTaoSavedDraft) -> TicketEditorLaunch {
        switch draft.content {
        case .bug(let bug): .newBug(accountId: draft.accountId, productId: bug.product, draftId: draft.id)
        case .task(let task): .newTask(accountId: draft.accountId, executionId: task.execution, draftId: draft.id)
        }
    }

    /// The ZenTao id inside a WorkNexus ticket id (`{accountId}:{type}:{id}`); a bare id comes back as it is.
    public static func zenTaoId(from ticketId: String) -> String {
        ticketId.split(separator: ":", omittingEmptySubsequences: false).last.map(String.init) ?? ticketId
    }
}
