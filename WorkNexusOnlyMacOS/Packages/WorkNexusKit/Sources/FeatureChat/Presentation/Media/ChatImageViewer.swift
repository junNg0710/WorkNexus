/// Ported from: lib/features/chat/presentation/widgets/{chat_image_viewer,chat_image_viewer_bar,chat_image_stage,chat_image_context_menu}.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// Full-size media viewer sheet, as large as most of the window it opens over. Pictures: zoom (buttons, pinch, double-click to
/// fit), rotate, drag to pan; a GIF or an animated WebP plays. Videos play on the stage with their controls. Previous/next
/// among the chat's pictures and videos (the arrows at the sides, or the strip of thumbnails along the bottom) - stickers are
/// left out. Save a copy, copy, save as sticker and open in the default app. Keys: ←/→, +/−, 0 (fit), R (rotate), Esc.
struct ChatImageViewer: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.dismiss) private var dismiss
    let accountId: String
    let chatGid: String
    @State var item: ChatMediaItem
    @State private var items: [ChatMediaItem] = []
    @State private var data: Data?
    /// The picture decoded once per load (not on every redraw).
    @State private var picture: NSImage?
    /// The picture has frames to play (a GIF, an animated WebP).
    @State private var animated = false
    @State private var hovering = false
    /// Most of the window it opens over, at the size picked with the bigger / smaller buttons.
    private var size: CGSize { ViewerSize.current(ViewerSizePreference.shared.level) }
    @State private var failed = false
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset = CGSize.zero
    /// Quarter turns clockwise.
    @State private var turns = 0
    @State private var dragStart = CGSize.zero
    @State private var note: String?

    private var content: MessageContent { item.content }
    private var index: Int? { items.firstIndex(of: item) }
    private var isVideo: Bool { if case .video = item { true } else { false } }

    init(accountId: String, chatGid: String, item: ChatMediaItem) {
        self.accountId = accountId; self.chatGid = chatGid; _item = State(initialValue: item)
    }

    private var actions: ChatImageViewerActions {
        ChatImageViewerActions(onZoom: zoom, onFit: fit, onRotate: rotate, onSaveAs: saveAs, onCopy: copy,
                               onSticker: services?.stickers == nil ? nil : saveSticker, onOpen: openExternally, onClose: { dismiss() },
                               pictureTools: !isVideo)
    }

    /// "3 / 11 · 2880 × 1800 · 1.2 MB": what is known of the picture on show.
    private var facts: String {
        var parts: [String] = []
        if let i = index, items.count > 1 { parts.append("\(i + 1) / \(items.count)") }
        if let rep = picture?.representations.first, rep.pixelsWide > 0 { parts.append("\(rep.pixelsWide) × \(rep.pixelsHigh)") }
        else if case .image(let image) = item, let w = image.width, let h = image.height, w > 0 { parts.append("\(w) × \(h)") }
        if item.size > 0 { parts.append(AttachmentActions.byteCount(item.size)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatImageViewerBar(name: item.name, facts: facts, note: note, zoom: scale, actions: actions)
            ZStack {
                theme.colors.scrim.opacity(0.92)
                if case .video(let file) = item {
                    ChatViewerVideoStage(accountId: accountId, file: file).id(file)
                } else if let picture {
                    ChatViewerPicture(picture: picture, data: animated ? data : nil).padding(theme.spacing.s16)
                        .rotationEffect(.degrees(Double(turns) * 90)).scaleEffect(scale).offset(offset)
                        .gesture(DragGesture().onChanged { offset = CGSize(width: dragStart.width + $0.translation.width, height: dragStart.height + $0.translation.height) }
                            .onEnded { _ in dragStart = offset })
                        .gesture(MagnifyGesture().onChanged { scale = max(0.2, min(8, base * $0.magnification)) }.onEnded { _ in base = scale })
                        .onTapGesture(count: 2) { fit() }
                } else if failed {
                    Text(appString("chatAttachmentFailed", "Couldn't load the attachment")).foregroundStyle(theme.colors.onScrim)
                } else { ProgressView().tint(theme.colors.onScrim) }
                if items.count > 1 {
                    HStack {
                        ChatImageStageArrow(next: false) { step(-1) }
                        Spacer(minLength: 0)
                        ChatImageStageArrow(next: true) { step(1) }
                    }
                    .opacity(hovering ? 1 : 0)
                    .animation(.easeOut(duration: theme.motion.fast), value: hovering)
                }
            }
            .clipped()
            .onHover { hovering = $0 }
            if items.count > 1 { ChatImageStrip(accountId: accountId, items: items, current: item) { item = $0 } }
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: theme.motion.base), value: ViewerSizePreference.shared.level)
        .background(theme.colors.scrim)
        .task(id: item) { await load() }
        .task { await loadSiblings() }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(characters: ["+", "="]) { _ in zoom(1.25); return isVideo ? .ignored : .handled }
        .onKeyPress(characters: ["-"]) { _ in zoom(1 / 1.25); return isVideo ? .ignored : .handled }
        .onKeyPress(characters: ["0"]) { _ in fit(); return isVideo ? .ignored : .handled }
        .onKeyPress(characters: ["r", "R"]) { _ in rotate(); return isVideo ? .ignored : .handled }
        .focusable().focusEffectDisabled()
    }

    private func fit() { scale = 1; base = 1; offset = .zero; dragStart = .zero }
    private func rotate() { turns = (turns + 1) % 4 }
    private func zoom(_ factor: CGFloat) { scale = max(0.2, min(8, scale * factor)); base = scale }

    private func load() async {
        data = nil; picture = nil; animated = false; failed = false; fit(); turns = 0
        guard case .image(let image) = item else { return }
        guard let repo = services?.chat else { failed = true; return }
        if let b64 = image.inlineBase64, let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) { show(d); return }
        switch await repo.loadAttachment(accountId: accountId, content: content, thumbnail: false) {
        case .success(let d): show(d)
        case .failure: failed = true
        }
    }

    private func show(_ d: Data) {
        data = d
        picture = NSImage(data: d)
        animated = StickerDecoder.isAnimated(d)
        if picture == nil { failed = true }
    }

    /// A confirmation beside the name, gone after a moment.
    private func say(_ text: String) {
        note = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if note == text { note = nil }
        }
    }

    /// The chat's loaded pictures and videos, for previous/next; stickers are left out.
    private func loadSiblings() async {
        guard let repo = services?.chat else { return }
        var stickerNames: Set<String> = []
        if case .success(let known)? = await services?.stickers?.stickers() { stickerNames = Set(known.map(\.name)) }
        for await messages in repo.watchAttachments(accountId: accountId, chatGid: chatGid) {
            items = ListViewerMedia()(messages, current: item, stickerNames: stickerNames)
            return
        }
    }

    private func step(_ d: Int) {
        guard let i = index, !items.isEmpty else { return }
        item = items[(i + d + items.count) % items.count]
    }

    private func saveAs() {
        guard let repo = services?.chat else { return }
        Task {
            switch await AttachmentActions.saveAs(TransferKey(accountId: accountId, content: content), name: item.name, repo) {
            case .success?: say(appString("chatSaved", "Saved"))
            case .failure(let f)?: say(f.message)
            case nil: break
            }
        }
    }

    private func copy() {
        guard let data else { return }
        copyImageToClipboard(data)
        say(appString("chatCopied", "Copied"))
    }

    private func saveSticker() {
        guard let repo = services?.chat, let stickers = services?.stickers else { return }
        Task {
            switch await SaveImageAsSticker(repo, stickers)(accountId: accountId, content: content) {
            case .success: say(appString("chatStickerSaved", "Saved to your stickers"))
            case .failure(let f): say(f.message)
            }
        }
    }

    private func openExternally() {
        guard let repo = services?.chat else { return }
        Task {
            if case .success(let path)? = await AttachmentTransfers.shared.download(TransferKey(accountId: accountId, content: content), repo) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        }
    }
}
