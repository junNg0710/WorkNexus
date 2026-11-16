import CoreDomain
import CoreTools
import Foundation

/// The ZenTao services the editor talks to, taken from `AppServices` (interfaces only). The ZenTao editor is
/// optional in `AppServices`; without it the editor shows its error state (it never crashes). Without a draft
/// repository the editor simply does not keep drafts.
public struct TicketEditorGateway: Sendable {
    public var editor: ZenTaoTicketEditor?
    public var drafts: ZenTaoTicketDraftRepository?
    public var members: ZenTaoTeamMembers?

    public init(editor: ZenTaoTicketEditor?, drafts: ZenTaoTicketDraftRepository? = nil, members: ZenTaoTeamMembers? = nil) {
        self.editor = editor; self.drafts = drafts; self.members = members
    }

    /// From the optional ZenTao hooks of `AppServices` (`zentaoEditor`, `zentaoDrafts`, `zentaoTeamMembers`).
    public init(services: AppServices?) {
        self.init(editor: services?.zentaoEditor, drafts: services?.zentaoDrafts, members: services?.zentaoTeamMembers)
    }

    public static let unavailable = Failure.unexpected("The ZenTao editor is not available for this build.")

    /// The editor service, or why there is none.
    public func requireEditor() -> Outcome<ZenTaoTicketEditor> {
        editor.map { .success($0) } ?? .failure(Self.unavailable)
    }
}
