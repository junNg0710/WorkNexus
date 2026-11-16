/// Ported from: lib/features/chat/presentation/widgets/{chat_image_viewer,chat_image_viewer_bar,chat_image_stage,chat_image_context_menu}.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// Full-size image viewer sheet: zoom (buttons, pinch, double-click to fit), rotate, drag to pan, previous/next among the chat's
/// images (arrows, or the strip of thumbnails along the bottom), save a copy, copy, save as sticker and open in the default app.
/// Keys: ←/→, +/−, 0 (fit), R (rotate), Esc.
struct ChatImageViewer: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.dismiss) private var dismiss
    let accountId: String
    let chatGid: String
    @State var image: ImageContent
    @State private var images: [ImageContent] = []
    @State private var data: Data?
    @State private var failed = false
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset = CGSize.zero
    /// Quarter turns clockwise.
    @State private var turns = 0
    @State private var dragStart = CGSize.zero
    @State private var note: String?

    private var content: MessageContent { .image(image) }
    private var index: Int? { images.firstIndex(of: image) }

    init(accountId: String, chatGid: String, image: ImageContent) {
        self.accountId = accountId; self.chatGid = chatGid; _image = State(initialValue: image)
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewerBar(name: image.name, position: index.map { ($0 + 1, images.count) }, note: note,
                      canStep: images.count > 1, onStep: step, onZoom: zoom, onFit: fit, onRotate: rotate, onSaveAs: saveAs, onCopy: copy,
                      onSticker: services?.stickers == nil ? nil : saveSticker, onOpen: openExternally, onClose: { dismiss() })
            ZStack {
                theme.colors.scrim.opacity(0.9)
                if let data, let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .rotationEffect(.degrees(Double(turns) * 90)).scaleEffect(scale).offset(offset)
                        .gesture(DragGesture().onChanged { offset = CGSize(width: dragStart.width + $0.translation.width, height: dragStart.height + $0.translation.height) }
                            .onEnded { _ in dragStart = offset })
                        .gesture(MagnifyGesture().onChanged { scale = max(0.2, min(8, base * $0.magnification)) }.onEnded { _ in base = scale })
                        .onTapGesture(count: 2) { fit() }
                } else if failed {
                    Text(appString("chatAttachmentFailed", "Couldn't load the attachment")).foregroundStyle(theme.colors.onScrim)
                } else { ProgressView().tint(theme.colors.onScrim) }
            }
            .clipped()
            if images.count > 1 { ChatImageStrip(accountId: accountId, images: images, current: image) { image = $0 } }
        }
        .frame(minWidth: 720, idealWidth: 960, minHeight: 520, idealHeight: 680)
        .background(theme.colors.card)
        .task(id: image) { await load() }
        .task { await loadSiblings() }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(characters: ["+", "="]) { _ in zoom(1.25); return .handled }
        .onKeyPress(characters: ["-"]) { _ in zoom(1 / 1.25); return .handled }
        .onKeyPress(characters: ["0"]) { _ in fit(); return .handled }
        .onKeyPress(characters: ["r", "R"]) { _ in rotate(); return .handled }
        .focusable().focusEffectDisabled()
    }

    private func fit() { scale = 1; base = 1; offset = .zero; dragStart = .zero }
    private func rotate() { turns = (turns + 1) % 4 }
    private func zoom(_ factor: CGFloat) { scale = max(0.2, min(8, scale * factor)); base = scale }

    private func load() async {
        data = nil; failed = false; fit(); turns = 0
        guard let repo = services?.chat else { failed = true; return }
        if let b64 = image.inlineBase64, let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) { data = d; return }
        switch await repo.loadAttachment(accountId: accountId, content: content, thumbnail: false) {
        case .success(let d): data = d
        case .failure: failed = true
        }
    }

    /// The chat's loaded images, for previous/next.
    private func loadSiblings() async {
        guard let repo = services?.chat else { return }
        for await messages in repo.watchAttachments(accountId: accountId, chatGid: chatGid) {
            images = messages.compactMap { $0.deleted ? nil : $0.content.asImage }
            return
        }
    }

    private func step(_ d: Int) {
        guard let i = index, !images.isEmpty else { return }
        image = images[(i + d + images.count) % images.count]
    }

    private func saveAs() {
        guard let repo = services?.chat else { return }
        Task {
            switch await AttachmentActions.saveAs(TransferKey(accountId: accountId, content: content), name: image.name, repo) {
            case .success?: note = appString("chatSaved", "Saved")
            case .failure(let f)?: note = f.message
            case nil: break
            }
        }
    }

    private func copy() {
        guard let data else { return }
        copyImageToClipboard(data)
        note = appString("chatCopied", "Copied")
    }

    private func saveSticker() {
        guard let repo = services?.chat, let stickers = services?.stickers else { return }
        Task {
            switch await SaveImageAsSticker(repo, stickers)(accountId: accountId, content: content) {
            case .success: note = appString("chatStickerSaved", "Saved to your stickers")
            case .failure(let f): note = f.message
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

private struct ViewerBar: View {
    @Environment(\.appTheme) private var theme
    let name: String
    let position: (Int, Int)?
    let note: String?
    let canStep: Bool
    let onStep: (Int) -> Void
    let onZoom: (CGFloat) -> Void
    let onFit: () -> Void
    let onRotate: () -> Void
    let onSaveAs: () -> Void
    let onCopy: () -> Void
    let onSticker: (() -> Void)?
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s4) {
            Text(name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
            if let position { Text("\(position.0) / \(position.1)").font(theme.typography.meta).foregroundStyle(theme.colors.tx3) }
            if let note { Text(note).font(theme.typography.meta).foregroundStyle(theme.colors.accent).padding(.leading, theme.spacing.s8) }
            Spacer(minLength: theme.spacing.s8)
            if canStep {
                AppIconButton("chevron.left", help: appString("chatPrevious", "Previous")) { onStep(-1) }
                AppIconButton("chevron.right", help: appString("chatNext", "Next")) { onStep(1) }
            }
            AppIconButton("minus.magnifyingglass", help: appString("chatZoomOut", "Zoom out")) { onZoom(1 / 1.25) }
            AppIconButton("plus.magnifyingglass", help: appString("chatZoomIn", "Zoom in")) { onZoom(1.25) }
            AppIconButton("arrow.up.left.and.arrow.down.right", help: appString("chatZoomFit", "Fit to screen"), action: onFit)
            AppIconButton("rotate.right", help: appString("chatRotate", "Rotate"), action: onRotate)
            AppIconButton("square.and.arrow.down", help: appString("chatSaveAs", "Save as…"), action: onSaveAs)
            AppIconButton("doc.on.doc", help: appString("chatCopyImage", "Copy image"), action: onCopy)
            if let onSticker { AppIconButton("face.smiling", help: appString("chatSaveSticker", "Save as sticker"), action: onSticker) }
            AppIconButton("arrow.up.forward.app", help: appString("chatOpenWith", "Open in default app"), action: onOpen)
            AppIconButton("xmark", help: appString("chatClosePanel", "Close"), action: onClose)
        }
        .padding(.horizontal, theme.spacing.s12)
        .frame(height: theme.sizes.titleBar - theme.spacing.s8)
        .background(theme.colors.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}
