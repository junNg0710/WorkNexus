/// Ported from: lib/shared/detail/presentation/widgets/action_dialog_scaffold.dart (`ActionScaffold`, `NoteField`,
/// `AssigneeDropdown`, `providerUsersProvider`), ticket_note_field.dart
import CoreDomain
import CoreUI
import Foundation
import Observation
import SwiftUI

/// Shared chrome for the ZenTao action dialogs: the app dialog frame with Cancel and the submit action.
struct ZentaoActionFrame<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String; let icon: String?; let submitLabel: String; let busy: Bool; let canSubmit: Bool
    let onSubmit: () -> Void; let onClose: () -> Void; let content: Content

    init(title: String, icon: String? = nil, submitLabel: String, busy: Bool, canSubmit: Bool = true,
         onSubmit: @escaping () -> Void, onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.submitLabel = submitLabel; self.busy = busy; self.canSubmit = canSubmit
        self.onSubmit = onSubmit; self.onClose = onClose; self.content = content()
    }

    var body: some View {
        AppDialogFrame(title: title, leadingIcon: icon, maxWidth: theme.sizes.dialogMd, onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(EdgeInsets(top: theme.spacing.s4, leading: theme.spacing.s24, bottom: theme.spacing.s24, trailing: theme.spacing.s24))
            }
            .frame(maxHeight: 560)
        } actions: {
            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.small) }
            AppButton(appString("cancel", "Cancel"), kind: .ghost, action: onClose).disabled(busy)
            AppButton(submitLabel, kind: .primary, action: onSubmit).disabled(busy || !canSubmit)
        }
    }
}

/// The gap between two fields of an action dialog.
struct ZentaoFieldGap: View {
    @Environment(\.appTheme) private var theme
    var body: some View { Color.clear.frame(height: theme.spacing.s16) }
}

/// The note an action dialog sends with its action. ZenTao takes it as HTML (its own forms use a rich editor), so it
/// is rich there; plain text elsewhere.
@MainActor @Observable
final class ZentaoNoteModel {
    @ObservationIgnored let rich: Bool
    @ObservationIgnored let html = HtmlEditingController()
    var text = ""
    init(ticket: Ticket) { rich = ticket.providerType == .zentao }
    /// What to send: HTML when rich, else the text.
    var value: String { rich ? html.html : text }
}

/// An action dialog's note field: a rich editor whose pasted or picked images are uploaded to the ticket's ZenTao, or
/// a plain text field.
struct ZentaoNoteField: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let ticket: Ticket; @Bindable var note: ZentaoNoteModel
    /// Takes files dropped on the editor that are not images (nil: only images, inline).
    var onDropFiles: (([DroppedFile]) -> Void)?
    // ZenTao files uploads under a form id; one per field is enough.
    @State private var uid = String(Int(Date().timeIntervalSince1970 * 1_000_000), radix: 16)

    var body: some View {
        let hint = appString("taskDetailNoteHint", "Optional note…")
        if note.rich {
            let deps = deps, ticket = ticket, uid = uid
            RichTextEditor(
                controller: note.html,
                imageLoader: { url in await Self.loadImage(deps, ticket, url) },
                onUploadImage: { data, name in
                    if case .success(let url) = await deps.editor.uploadImage(accountId: ticket.accountId, uid: uid, bytes: data, fileName: name) { return url }
                    return nil
                },
                onDropFiles: onDropFiles, minHeight: 96, placeholder: hint)
        } else {
            TextField(hint, text: $note.text, axis: .vertical).lineLimit(3...6).textFieldStyle(.plain)
                .font(theme.typography.body).padding(theme.spacing.s8)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
    }

    private static func loadImage(_ deps: ZentaoDependencies, _ ticket: Ticket, _ url: String) async -> Data? {
        if let data = await deps.editor.loadImage(accountId: ticket.accountId, url: url) { return data }
        guard let account = await deps.account(id: ticket.accountId), let adapter = await deps.services.sync.adapter(for: account) else { return nil }
        return await adapter.fetchBytes(url: url, projectPath: nil, projectId: nil)
    }
}

/// The people a ZenTao ticket can be handed to: the members of its execution (task) or product (bug) when ZenTao
/// lists them, else the account's whole user list.
enum ZentaoAssignees {
    static func load(_ deps: ZentaoDependencies, _ ticket: Ticket) async -> Outcome<[ProviderUser]> {
        var members: Outcome<[ProviderUser]>?
        switch ticket.providerEntity {
        case .zentaoTask(let t): if let e = zentaoLinkId(t.execution) { members = await deps.teamMembers.executionMembers(accountId: ticket.accountId, executionId: e) }
        case .zentaoBug(let b): if let p = zentaoLinkId(b.product) { members = await deps.teamMembers.productMembers(accountId: ticket.accountId, productId: p) }
        default: break
        }
        if let list = members?.value, !list.isEmpty { return .success(list) }
        guard let account = await deps.account(id: ticket.accountId), let adapter = await deps.services.sync.adapter(for: account) else {
            return .failure(.auth("No stored credentials for this account"))
        }
        return await adapter.listUsers()
    }
}

/// A themed assignee picker fed by `ZentaoAssignees`; `value` is a login (`ProviderUser.account`).
struct ZentaoAssigneeDropdown: View {
    let deps: ZentaoDependencies; let ticket: Ticket; let value: String?; let onChanged: (String) -> Void
    @State private var users: ZentaoLoad<[ProviderUser]> = .loading

    var body: some View {
        Group {
            switch users {
            case .loading: AppInlineSpinner()
            case .failed: AppInlineNote(appString("taskDetailUsersLoadFailed", "Couldn't load users"), isError: true)
            case .loaded(let list):
                SearchableDropdownField(
                    items: list, value: list.first { $0.account == value },
                    labelOf: { $0.displayName }, searchTextOf: { "\($0.displayName) \($0.account)" },
                    hintText: appString("taskDetailSelectUser", "Select a user"), searchHint: appString("searchUsers", "Search users…"),
                    emptyLabel: appString("noMatchingUsers", "No matching users")) { onChanged($0.account) }
            }
        }
        .task(id: ticket.id) {
            switch await ZentaoAssignees.load(deps, ticket) {
            case .success(let l): users = .loaded(l)
            case .failure(let f): users = .failed(f)
            }
        }
    }
}
