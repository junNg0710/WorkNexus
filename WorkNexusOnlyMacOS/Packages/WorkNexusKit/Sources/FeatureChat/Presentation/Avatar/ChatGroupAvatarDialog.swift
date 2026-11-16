/// Ported from: lib/features/chat/presentation/widgets/chat_group_avatar_dialog.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// Changes a group's picture: a short text on a colour, or an image.
struct ChatGroupAvatarDialog: View {
    /// Colours offered for a text avatar — the official client's palette, so both clients show the same choices. Data sent
    /// to the server, not theme colours, hence the literals.
    static let colors = ["#37C3A4", "#66ADFF", "#E05151", "#E0B751", "#A2E051", "#51E067", "#7C51E0", "#E051DE", "#E05177", "#E09A51"]

    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let chat: ChatConversation
    let title: String
    @State private var text: String
    @State private var hex: String
    @State private var imageMode = false
    @State private var image: Data?
    @State private var saving = false

    init(model: ChatShellModel, chat: ChatConversation, title: String) {
        self.model = model; self.chat = chat; self.title = title
        if case .text(let t, let c)? = ChatGroupAvatar.from(json: chat.avatarJson) {
            _text = State(initialValue: t); _hex = State(initialValue: Self.colors.contains(c) ? c : Self.colors[0])
        } else {
            _text = State(initialValue: ""); _hex = State(initialValue: Self.colors[0])
        }
    }

    private var canSave: Bool { !saving && !(imageMode && image == nil) }

    var body: some View {
        AppDialogFrame(title: shellString("chatChangeGroupAvatar", "Change group picture"), maxWidth: theme.sizes.dialogSm, onClose: close) {
            VStack(spacing: theme.spacing.s16) {
                SettingsLikeSegmented(options: [(false, shellString("chatAvatarText", "Text")), (true, shellString("chatAvatarImage", "Image"))],
                                      value: imageMode) { imageMode = $0 }
                preview
                if imageMode {
                    AppButton(shellString("chatAvatarPick", "Choose an image"), systemImage: "photo") { image = model.pickImageData() ?? image }
                } else {
                    TextField(shellString("chatAvatarTextHint", "Up to 4 characters"), text: Binding(get: { text }, set: { text = String($0.prefix(4)) }))
                        .textFieldStyle(.roundedBorder).onSubmit { if canSave { Task { await save() } } }
                    FlowLayout(spacing: theme.spacing.s8) {
                        ForEach(Self.colors, id: \.self) { c in
                            AppSwatchButton(size: theme.sizes.control32, color: ChatShellLabels.hexColor(c).map { Color(argb: 0xFF00_0000 | $0) },
                                            selected: c == hex, help: c) { hex = c }
                        }
                    }
                }
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s16)
        } actions: {
            Spacer(minLength: 0)
            AppButton(shellString("chatCancel", "Cancel"), kind: .ghost, action: close)
            AppButton(shellString("chatSave", "Save"), kind: .primary) { Task { await save() } }.disabled(!canSave)
        }
    }

    @ViewBuilder private var preview: some View {
        let side = theme.sizes.control36 * 2 + theme.spacing.s12
        if imageMode, let image, let ns = NSImage(data: image) {
            Image(nsImage: ns).resizable().scaledToFill().frame(width: side, height: side).clipShape(Circle())
        } else if imageMode {
            ChatAvatarView(name: title, diameter: side)
        } else {
            ChatAvatarView(name: title, style: ChatAvatarStyle(label: text, background: ChatShellLabels.hexColor(hex)), diameter: side)
        }
    }

    private func close() { model.groupAvatarChat = nil }

    private func save() async {
        saving = true
        let result = await model.repository.setGroupAvatar(accountId: chat.accountId, chatGid: chat.gid,
                                                           text: imageMode ? nil : text.trimmingCharacters(in: .whitespaces),
                                                           color: imageMode ? nil : hex, image: imageMode ? image : nil)
        switch result {
        case .success: close()
        case .failure(let f): saving = false; model.report(f)
        }
    }
}

/// A two-way segmented choice.
private struct SettingsLikeSegmented: View {
    let options: [(Bool, String)]
    let value: Bool
    let onChange: (Bool) -> Void
    var body: some View {
        AppSegmentedTabs(options.map { o in AppSegmentedTab(label: o.1, active: o.0 == value) { onChange(o.0) } })
    }
}
