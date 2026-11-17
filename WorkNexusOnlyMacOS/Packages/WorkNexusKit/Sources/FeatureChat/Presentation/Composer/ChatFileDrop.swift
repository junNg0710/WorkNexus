/// Not in the Flutter app (its composer took dropped files only).
import AppKit
import CoreUI
import SwiftUI
import UniformTypeIdentifiers

/// What a drop onto the chat brings: files from Finder, or a picture dragged out of another app (a browser image, the
/// screenshot thumbnail) that has no file behind it.
enum ChatDrop {
    static let types: [UTType] = [.fileURL, .image]
    /// Kinds of picture sent as they are; anything else (TIFF, HEIC…) goes as PNG, which every client shows.
    private static let kept: [UTType] = [.png, .jpeg, .gif, .webP]

    /// The dropped items as files to send, in order; one that cannot be read is left out.
    static func read(_ providers: [NSItemProvider], now: Date = Date()) async -> [StagedFile] {
        var out: [StagedFile] = []
        for (i, provider) in providers.enumerated() {
            if let file = await read(provider, fallbackName: "dropped-\(Int(now.timeIntervalSince1970 * 1000))\(i == 0 ? "" : "-\(i)")") {
                out.append(file)
            }
        }
        return out
    }

    private static func read(_ provider: NSItemProvider, fallbackName: String) async -> StagedFile? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { done in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in done.resume(returning: url) }
            }
            if let url, let file = ChatStaging.staged(from: url) { return file }
        }
        let type = provider.registeredTypeIdentifiers.compactMap(UTType.init).first { $0.conforms(to: .image) }
        guard let type else { return nil }
        let data: Data? = await withCheckedContinuation { done in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in done.resume(returning: data) }
        }
        guard let data, !data.isEmpty else { return nil }
        let base = ((provider.suggestedName ?? fallbackName) as NSString).deletingPathExtension
        if let same = kept.first(where: { type.conforms(to: $0) }), let ext = same.preferredFilenameExtension {
            let name = "\(base).\(ext)"
            return StagedFile(name: name, data: data, mimeType: ChatStaging.mimeType(forName: name))
        }
        guard let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return StagedFile(name: "\(base).png", data: png, mimeType: "image/png")
    }
}

extension View {
    /// Takes files and pictures dropped anywhere on the chat (messages or input) into the input, ready to send.
    func chatFileDrop(state: ChatThreadState) -> some View { modifier(ChatFileDropModifier(state: state)) }
}

private struct ChatFileDropModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    let state: ChatThreadState
    @State private var targeted = false

    /// A read-only chat, or one in "Multiple select", takes nothing.
    private var accepts: Bool {
        CanSendToChat()(state.chat, selfUserId: state.selfUserId, selfAccount: state.selfAccount) && !state.isSelecting
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted && accepts {
                    FileDropOverlay(hint: appString("dropFilesToStage", "Drop files to add them to the message"), active: true)
                        .padding(theme.spacing.s8).allowsHitTesting(false)
                }
            }
            .onDrop(of: ChatDrop.types, isTargeted: $targeted) { providers in
                guard accepts, !providers.isEmpty else { return false }
                Task { @MainActor in
                    let files = await ChatDrop.read(providers)
                    if !files.isEmpty { state.stagedFiles.append(contentsOf: files) }
                }
                return true
            }
    }
}
