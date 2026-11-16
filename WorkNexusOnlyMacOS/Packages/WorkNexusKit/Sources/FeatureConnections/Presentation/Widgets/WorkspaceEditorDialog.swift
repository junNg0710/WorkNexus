import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/presentation/widgets/workspace_editor_dialog.dart
/// Edits a workspace's name, badge letters, colour and icon (a picked image file is kept as a
/// `data:image/...;base64,` icon key, at most 256 KB). `RenameWorkspace` decides what is acceptable.
struct WorkspaceEditorDialog: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var name: String
    @State private var code: String
    @State private var colorValue: Int
    @State private var iconKey: String
    @State private var iconFileName: String?
    let workspace: Workspace
    /// The dialog's title and its save button: "Edit workspace" / "Save", or "Create workspace" / "Create & join".
    let title: String
    let saveTitle: String
    let onSave: (Workspace) -> Void
    let onClose: () -> Void

    static let maxIconBytes = 256 * 1024

    init(workspace: Workspace, title: String = L.editTitle, saveTitle: String = L.save,
         onSave: @escaping (Workspace) -> Void, onClose: @escaping () -> Void) {
        self.workspace = workspace; self.title = title; self.saveTitle = saveTitle; self.onSave = onSave; self.onClose = onClose
        _name = State(initialValue: workspace.name); _code = State(initialValue: workspace.shortCode)
        _colorValue = State(initialValue: workspace.colorValue); _iconKey = State(initialValue: workspace.iconKey)
    }

    /// The personal workspace has no name to edit.
    private var canSave: Bool { workspace.isPersonal || !name.trimmed.isEmpty }

    /// The letters both badges show: the typed ones, else those of the name.
    private var badgeCode: String {
        let typed = code.trimmed
        return typed.isEmpty ? RenameWorkspace.shortCode(of: name) : typed.uppercased()
    }

    var body: some View {
        let c = theme.colors, s = theme.spacing
        AppDialogFrame(title: title, maxWidth: theme.sizes.dialogMd, onClose: onClose) {
            VStack(alignment: .leading, spacing: s.s16) {
                HStack(spacing: s.s10) {
                    WorkspaceBadge(Color(argb: UInt32(truncatingIfNeeded: colorValue)), badgeCode, big: true, iconKey: iconKey)
                    if workspace.isPersonal {
                        Text(L.personal).font(theme.typography.bodyStrong).foregroundStyle(c.tx)
                    } else {
                        VStack(alignment: .leading, spacing: s.s2) {
                            ConnectionTextField(label: L.nameLabel, text: $name, hint: L.nameLabel, autofocus: true)
                            if name.trimmed.isEmpty { Text(L.nameRequired).font(theme.typography.caption).foregroundStyle(c.red) }
                        }
                    }
                }
                ConnectionTextField(label: L.codeLabel, text: $code, hint: RenameWorkspace.shortCode(of: name))
                    .frame(width: theme.sizes.control36 * 3)
                VStack(alignment: .leading, spacing: s.s6) {
                    Text(L.color).font(theme.typography.label).foregroundStyle(c.tx2)
                    FlowLayout(spacing: s.s6) {
                        ForEach(WorkspaceIcons.colorChoices, id: \.self) { v in
                            WorkspaceColorChoice(value: Int(v), selected: Int(v) == colorValue) { colorValue = Int(v) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: s.s6) {
                    Text(L.icon).font(theme.typography.label).foregroundStyle(c.tx2)
                    WorkspaceIconFilePicker(colorValue: colorValue, shortCode: badgeCode, iconKey: iconKey, fileName: iconFileName,
                                            onPick: pickIcon, onClear: WorkspaceIcons.imageData(iconKey) == nil ? nil : {
                        iconKey = "briefcase"; iconFileName = nil
                    })
                }
            }
            .padding(.horizontal, s.s24).padding(.bottom, s.s24)
        } actions: {
            Spacer(minLength: 0)
            AppButton(L.cancel, kind: .ghost, action: onClose)
            AppButton(saveTitle, kind: .primary, action: save).disabled(!canSave).opacity(canSave ? 1 : 0.5)
        }
    }

    private func save() {
        var w = workspace
        w.colorValue = colorValue; w.iconKey = iconKey
        switch RenameWorkspace()(WorkspaceRename(workspace: w, name: name, shortCode: code)) {
        case .success(let renamed): onSave(renamed)
        case .failure(let f): toasts?.show(Self.refusal(f), kind: .error)
        }
    }

    /// Why `RenameWorkspace` refused, in the user's language.
    static func refusal(_ failure: Failure) -> String {
        var fields: [String: String] = [:]
        if case .validation(_, let f) = failure { fields = f }
        if fields[RenameWorkspace.codeField] == RenameWorkspace.tooLong { return L.codeTooLong(RenameWorkspace.maxCodeLength) }
        if fields[RenameWorkspace.nameField] == RenameWorkspace.tooLong { return L.nameTooLong(RenameWorkspace.maxNameLength) }
        return L.nameRequired
    }

    private func pickIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .gif]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        guard data.count <= Self.maxIconBytes else { toasts?.show(L.iconTooLarge, kind: .error); return }
        iconKey = "data:\(Self.mimeType(url.lastPathComponent));base64,\(data.base64EncodedString())"
        iconFileName = url.lastPathComponent
    }

    static func mimeType(_ file: String) -> String {
        let lower = file.lowercased()
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        return "image/png"
    }
}
