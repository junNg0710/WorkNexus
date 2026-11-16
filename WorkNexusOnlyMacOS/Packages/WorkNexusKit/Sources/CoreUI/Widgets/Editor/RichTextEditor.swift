import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Ported from: lib/core/widgets/rich_text_editor.dart
/// Uploads an image put into the editor (picked or pasted) and returns the URL to show it at, or nil when it
/// could not be uploaded.
public typealias EditorImageUploader = @Sendable (Data, String) async -> String?

/// A rich-text editor with the formatting ZenTao's web editor offers — headings, bold / italic / underline /
/// strike, colours, lists, quotes, code, links, alignment, indent and images — reading and writing HTML through
/// `controller` (read `controller.html` when saving). `imageLoader` loads an image's bytes (authenticated) to show
/// it in the editor; `onUploadImage` uploads a picked or pasted image (images cannot be added without it).
/// Clipboard access defaults to the system pasteboard unless the controller was given its own.
public struct RichTextEditor: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var commands = RichEditorCommands()
    @State private var uploading = false
    @State private var reloadToken = 0
    let controller: HtmlEditingController
    let imageLoader: ImageBytesLoader?
    let onUploadImage: EditorImageUploader?
    let onDropFiles: (([DroppedFile]) -> Void)?
    let minHeight: CGFloat
    let placeholder: String?

    /// - Parameter onDropFiles: takes files dropped onto the editor that it cannot show inline (anything but an image,
    ///   or every file without `onUploadImage`); dropping is off when both are nil.
    public init(controller: HtmlEditingController, imageLoader: ImageBytesLoader? = nil, onUploadImage: EditorImageUploader? = nil,
                onDropFiles: (([DroppedFile]) -> Void)? = nil, minHeight: CGFloat = 220, placeholder: String? = nil) {
        self.controller = controller; self.imageLoader = imageLoader; self.onUploadImage = onUploadImage
        self.onDropFiles = onDropFiles; self.minHeight = minHeight; self.placeholder = placeholder
        if controller.readImage == nil { controller.readImage = { readClipboardImage() } }
        if controller.readClipboardText == nil { controller.readClipboardText = { NSPasteboard.general.string(forType: .string) } }
    }

    public var body: some View {
        FileDropTarget(hint: appString("dropFilesToInsert", "Drop images to insert, other files to attach"),
                       enabled: onUploadImage != nil || onDropFiles != nil, onDrop: drop) { editor }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            RichEditorToolbar(commands: commands, canInsertImage: onUploadImage != nil, uploading: uploading, onPickImage: pickImage)
            Divider().overlay(theme.colors.line)
            EditorSurface(controller: controller, commands: commands, theme: theme, imageLoader: imageLoader,
                          reloadToken: reloadToken, placeholder: placeholder)
                .frame(minHeight: minHeight)
        }
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
        .onAppear { installPasteUpload() }
    }

    private func installPasteUpload() {
        guard onUploadImage != nil else { return }
        controller.onImagePaste = { bytes in await upload(bytes, "pasted-\(Int(Date().timeIntervalSince1970 * 1000)).png") }
    }

    private func upload(_ bytes: Data, _ name: String) async -> String? {
        guard let upload = onUploadImage else { return nil }
        uploading = true
        let url = await upload(bytes, name)
        uploading = false
        if url == nil { toasts?.show(appString("imageUploadFailed", "Couldn't upload the image"), kind: .error) }
        return url
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .bmp]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let file = panel.url, let data = try? Data(contentsOf: file) else { return }
        Task { await insertImage(data, file.lastPathComponent) }
    }

    /// Uploads an image and puts it at the caret.
    private func insertImage(_ data: Data, _ name: String) async {
        guard let url = await upload(data, name) else { return }
        controller.document.insertImage(url, at: max(controller.selectionEnd, 0))
        controller.selectionEnd += 1
        reloadToken += 1
    }

    /// Images go inline (when they can be uploaded); the rest to `onDropFiles`.
    private func drop(_ files: [DroppedFile]) async {
        let canUpload = onUploadImage != nil
        let split = DroppedFiles.split(files)
        let others = split.others + (canUpload ? [] : split.images)
        if !others.isEmpty { onDropFiles?(others) }
        guard canUpload else { return }
        for image in split.images { await insertImage(image.bytes, image.name) }
    }
}

/// The `NSTextView` itself, kept in sync with the controller's `RichDocument`.
private struct EditorSurface: NSViewRepresentable {
    let controller: HtmlEditingController
    let commands: RichEditorCommands
    let theme: AppTheme
    let imageLoader: ImageBytesLoader?
    let reloadToken: Int
    let placeholder: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private var style: RichStyle {
        RichStyle(family: theme.typography.family, size: 14, ink: NSColor(theme.colors.tx), accent: NSColor(theme.colors.accent),
                  codeBackground: NSColor(theme.colors.tx).withAlphaComponent(0.08), quoteBar: NSColor(theme.colors.line2))
    }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = RichLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let tv = RichNSTextView(frame: .zero, textContainer: container)
        tv.isRichText = true; tv.allowsUndo = true; tv.drawsBackground = false
        tv.isVerticallyResizable = true; tv.isHorizontallyResizable = false; tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.isAutomaticQuoteSubstitutionEnabled = false; tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false; tv.isAutomaticTextReplacementEnabled = false
        tv.delegate = context.coordinator
        let scroll = NSScrollView()
        scroll.documentView = tv; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        context.coordinator.attach(tv, layout: layout)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyTheme()
        if context.coordinator.loadedToken != reloadToken { context.coordinator.reload() }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorSurface
        weak var textView: RichNSTextView?
        weak var layout: RichLayoutManager?
        var loadedToken: Int
        private var reloading = false

        init(_ p: EditorSurface) { parent = p; loadedToken = p.reloadToken }

        func attach(_ tv: RichNSTextView, layout: RichLayoutManager) {
            textView = tv; self.layout = layout
            tv.onPasteImage = { [weak self] in await self?.pasteImage() ?? false }
            parent.commands.textView = tv
            applyTheme()
            reload()
        }

        func applyTheme() {
            guard let tv = textView else { return }
            let s = parent.style
            layout?.style = s
            parent.commands.style = s
            tv.insertionPointColor = s.accent
            tv.placeholder = parent.placeholder
            tv.placeholderColor = NSColor(parent.theme.colors.tx3)
            tv.typingAttributes = RichAttributedBridge.attributes(inline: parent.commands.activeInline, block: parent.commands.activeBlock, style: s)
        }

        /// Replaces the view's text with the controller's document, keeping the caret.
        func reload() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            loadedToken = parent.reloadToken
            let caret = tv.selectedRange().location
            reloading = true
            let text = RichAttributedBridge.attributedString(from: parent.controller.document, style: parent.style) { inline in
                RichImageAttachment(url: inline.image ?? "", width: inline.imageWidth.flatMap(Double.init))
            }
            storage.setAttributedString(text)
            tv.setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
            reloading = false
            loadImages()
        }

        private func loadImages() {
            guard let tv = textView, let storage = tv.textStorage, let loader = parent.imageLoader else { return }
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                guard let att = value as? RichImageAttachment, !att.url.isEmpty, att.image == nil || att.isPlaceholder else { return }
                let url = att.url
                Task { @MainActor [weak self, weak att] in
                    guard let data = await loader(url), let img = NSImage(data: data), let att else { return }
                    let maxW = max((self?.textView?.bounds.width ?? 400) - 40, 80)
                    att.display(img, width: att.requestedWidth.map { CGFloat($0) }, maxWidth: maxW)
                    if let tv = self?.textView, let lm = tv.layoutManager { lm.invalidateLayout(forCharacterRange: NSRange(location: 0, length: tv.textStorage?.length ?? 0), actualCharacterRange: nil); tv.needsDisplay = true }
                }
            }
        }

        private func pasteImage() async -> Bool {
            syncFromView()
            let pasted = await parent.controller.pasteClipboardImage()
            if pasted { parent.controller.selectionEnd = textView?.selectedRange().upperBound ?? 0; loadedToken = -1; reload() }
            return pasted
        }

        func syncFromView() {
            guard let storage = textView?.textStorage, !reloading else { return }
            parent.controller.document = RichAttributedBridge.document(from: storage)
            parent.controller.selectionEnd = textView?.selectedRange().upperBound ?? 0
        }

        func textDidChange(_ notification: Notification) { syncFromView(); parent.commands.refresh() }
        func textViewDidChangeSelection(_ notification: Notification) {
            parent.controller.selectionEnd = textView?.selectedRange().upperBound ?? 0
            parent.commands.refresh()
        }
        /// Clicking a link while editing must not navigate away.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool { true }
    }
}

/// An inline image in the editor: shows a placeholder until its bytes arrive.
final class RichImageAttachment: NSTextAttachment {
    let url: String
    let requestedWidth: Double?
    private(set) var isPlaceholder = true

    init(url: String, width: Double?) {
        self.url = url; requestedWidth = width
        super.init(data: nil, ofType: nil)
        image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the loaded picture at `width` (or its natural size), capped to `maxWidth`.
    func display(_ img: NSImage, width: CGFloat?, maxWidth: CGFloat) {
        let natural = img.size
        let w = min(width ?? natural.width, maxWidth)
        let h = natural.width > 0 ? natural.height * w / natural.width : natural.height
        image = img; bounds = CGRect(x: 0, y: 0, width: w, height: h); isPlaceholder = false
    }
}
