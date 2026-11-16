import CoreDomain
import CoreTools
import SwiftUI

/// Everything the shared detail panel needs from features / tools it must not import (rule 10.1). Built once by the
/// composition root: FeatureTranslation supplies the Translation tab, FeatureTicketEditor the edit route, ZenTao the
/// authenticated image upload / avatars. Every hook is optional; the panel degrades gracefully without it.
public struct DetailExtensions {
    /// The "Translation" tab body (Flutter `TranslationTab`) and its footer (`TranslationFooter`).
    public var translationTab: ((Ticket, DetailLayout) -> AnyView)?
    public var translationFooter: ((Ticket) -> AnyView)?
    /// Label of the translation tab, e.g. "🇻🇳 Tiếng Việt" (the user's target language). nil hides the tab.
    public var translationTabLabel: (() -> String?)?
    /// Opens a ticket editor route for the "edit" button (`TicketEditorRoute`); default: ZenTao bugs / tasks.
    public var editRoute: ((Ticket) -> TicketEditorRoute?)?
    /// Uploads an image pasted into the rich comment editor (ZenTao) and returns its URL.
    public var uploadImage: (@Sendable (Ticket, Data, String) async -> String?)?
    /// Same as `uploadImage`, but told the upload id of the composer (ZenTao files uploads under a form id; one per
    /// composer, renewed after a comment is posted, as Flutter's composer keeps). Preferred over `uploadImage` when set.
    public var uploadImageWithUid: (@Sendable (Ticket, String, Data, String) async -> String?)?
    /// Fetches an inline image with the account's auth; default: the sync coordinator's cached fetch, else the adapter.
    public var imageLoader: (@Sendable (Ticket, String) async -> Data?)?
    /// Opens an attachment viewer (default: the built-in `AttachmentViewerDialog`).
    public var openAttachment: ((Ticket, TicketAttachment) -> Void)?
    /// Opens a link from the ticket (default: `openLinkExternally`).
    public var openLink: ((String) -> Void)?

    public init() {}

    func route(for t: Ticket) -> TicketEditorRoute? {
        if let editRoute { return editRoute(t) }
        guard t.providerType == .zentao else { return nil }
        switch t.externalType?.lowercased() {
        case "bug": return .editBug(accountId: t.accountId, ticketId: t.id)
        case "task": return .editTask(accountId: t.accountId, ticketId: t.id)
        default: return nil
        }
    }
}
