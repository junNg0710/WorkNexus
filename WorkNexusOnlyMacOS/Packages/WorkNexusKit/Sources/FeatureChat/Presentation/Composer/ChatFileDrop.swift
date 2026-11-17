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

/// Where a drop lands in a chat (as in the Flutter app): on the messages the files go out at once; on the input they wait
/// there to be sent.
enum ChatDropMode { case send, stage }

/// How many drop areas of an open chat files hover over: while they hover over either, both show their hints, the one
/// under the pointer highlighted, so the user sees what each does before letting go.
@MainActor @Observable
final class ChatDropZones { var hovering = 0 }

private struct ChatDropZonesKey: EnvironmentKey { static let defaultValue: ChatDropZones? = nil }
extension EnvironmentValues {
    var chatDropZones: ChatDropZones? {
        get { self[ChatDropZonesKey.self] }
        set { self[ChatDropZonesKey.self] = newValue }
    }
}

extension View {
    /// Groups the drop areas under it (`chatFileDrop`), so they show their hints together.
    func chatDropZones() -> some View { modifier(ChatDropZonesHost()) }
    /// Takes files and pictures dropped here: `.send` sends them at once, `.stage` puts them in the input.
    func chatFileDrop(state: ChatThreadState, mode: ChatDropMode) -> some View { modifier(ChatFileDropModifier(state: state, mode: mode)) }
}

private struct ChatDropZonesHost: ViewModifier {
    @State private var zones = ChatDropZones()
    func body(content: Content) -> some View { content.environment(\.chatDropZones, zones) }
}

private struct ChatFileDropModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.chatSettings) private var settings
    @Environment(\.toasts) private var toasts
    @Environment(\.chatDropZones) private var zones
    let state: ChatThreadState
    let mode: ChatDropMode
    @State private var targeted = false

    /// A read-only chat, or one in "Multiple select", takes nothing.
    private var accepts: Bool {
        CanSendToChat()(state.chat, selfUserId: state.selfUserId, selfAccount: state.selfAccount) && !state.isSelecting
    }

    private var hint: String {
        mode == .send ? appString("dropFilesToSend", "Drop files to send") : appString("dropFilesToStage", "Drop files to add them to the message")
    }

    func body(content: Content) -> some View {
        let shown = accepts && (targeted || (zones?.hovering ?? 0) > 0)
        content
            .overlay {
                if shown {
                    FileDropOverlay(hint: hint, active: targeted)
                        .padding(mode == .send ? theme.spacing.s8 : theme.spacing.s4).allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: theme.motion.fast), value: shown)
            .onDrop(of: ChatDrop.types, isTargeted: Binding(get: { targeted }, set: hover)) { providers in
                hover(false)
                guard accepts, !providers.isEmpty else { return false }
                Task { @MainActor in
                    let files = await ChatDrop.read(providers)
                    guard !files.isEmpty else { return }
                    switch mode {
                    case .stage: state.stagedFiles.append(contentsOf: files)
                    case .send:
                        guard let services else { return }
                        if case .failure(let f) = await ChatMessageSender(state: state, services: services, settings: settings).files(files) {
                            toasts?.show(f.message, kind: .error)
                        }
                    }
                }
                return true
            }
            .onDisappear { hover(false) }
    }

    private func hover(_ on: Bool) {
        guard on != targeted else { return }
        targeted = on
        if on { zones?.hovering += 1 } else { zones?.hovering = max((zones?.hovering ?? 1) - 1, 0) }
    }
}
