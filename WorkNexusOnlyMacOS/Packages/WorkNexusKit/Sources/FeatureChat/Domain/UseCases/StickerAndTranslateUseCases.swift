import CoreDomain
import Foundation

public struct ImportedStickerPack: Hashable, Sendable {
    public var pack: String, title: String
    public var added: Int, stills: Int, failed: Int
}

/// Imports a Telegram sticker set into the local sticker store: animated `.tgs` stickers are converted to animated WebP
/// (falling back to the still thumbnail), stills to WebP; results keep Telegram's order whatever the parallel work does.
/// Ported from: lib/features/chat/domain/usecases/import_sticker_pack.dart
public struct ImportStickerPack: Sendable {
    private let source: StickerPackSource, converter: StickerConverter, stickers: StickerRepository
    private let parallel: Int
    public init(_ source: StickerPackSource, _ converter: StickerConverter, _ stickers: StickerRepository, parallel: Int = 4) {
        self.source = source; self.converter = converter; self.stickers = stickers; self.parallel = parallel
    }

    public static func packId(of setName: String) -> String { "tg:\(setName)" }

    public func callAsFunction(_ link: String, token: String, onListed: (@Sendable (String, Int) -> Void)? = nil,
                               onProgress: (@Sendable (Int, Int) -> Void)? = nil) async -> Outcome<ImportedStickerPack> {
        guard let name = ParseStickerPackLink()(link) else { return .failure(.validation("Not a Telegram sticker link")) }
        let set: RemoteStickerSet
        switch await source.stickerSet(name: name, token: token) { case .success(let s): set = s; case .failure(let f): return .failure(f) }
        let total = set.stickers.count
        onListed?(set.title, total)
        let results = await withTaskGroup(of: (Int, Outcome<(bytes: Data, still: Bool)>).self) { group -> [Outcome<(bytes: Data, still: Bool)>?] in
            var out = [Outcome<(bytes: Data, still: Bool)>?](repeating: nil, count: total)
            var next = 0, done = 0
            func launch() {
                guard next < total else { return }
                let i = next; next += 1
                group.addTask { (i, await self.webp(set.stickers[i], token)) }
            }
            for _ in 0..<min(parallel, total) { launch() }
            while let (i, r) = await group.next() { out[i] = r; done += 1; onProgress?(done, total); launch() }
            return out
        }
        var files: [StickerFile] = []
        var stills = 0, failed = 0
        var lastFailure: CoreDomain.Failure?
        for (i, result) in results.enumerated() {
            switch result {
            case .success(let v)?:
                files.append((name: String(format: "%03d.webp", i + 1), bytes: v.bytes))
                if v.still { stills += 1 }
            case .failure(let f)?: failed += 1; lastFailure = f
            case nil: failed += 1
            }
        }
        guard !files.isEmpty else { return .failure(lastFailure ?? .notFound("The set is empty")) }
        let pack = Self.packId(of: set.name)
        switch await stickers.addPack(pack, title: set.title, stickers: files) {
        case .success: return .success(ImportedStickerPack(pack: pack, title: set.title, added: files.count, stills: stills, failed: failed))
        case .failure(let f): return .failure(f)
        }
    }

    private func webp(_ s: RemoteSticker, _ token: String) async -> Outcome<(bytes: Data, still: Bool)> {
        if s.kind == .still { return await fetch(s.fileId, token, still: false) }
        if s.kind == .animated, case .success(let tgs) = await source.file(fileId: s.fileId, token: token),
           case .success(let webp) = await converter.animatedToWebp(tgs: tgs) { return .success((webp, false)) }
        guard let thumb = s.thumbnailFileId else { return .failure(.notFound("No still image of this sticker")) }
        return await fetch(thumb, token, still: true)
    }

    private func fetch(_ fileId: String, _ token: String, still: Bool) async -> Outcome<(bytes: Data, still: Bool)> {
        let bytes: Data
        switch await source.file(fileId: fileId, token: token) { case .success(let b): bytes = b; case .failure(let f): return .failure(f) }
        // An image that cannot be scaled is still worth keeping as it came.
        let fitted = (await converter.imageToWebp(image: bytes)).value
        return .success((fitted ?? bytes, still))
    }
}

/// Ported from: lib/features/chat/domain/usecases/save_image_as_sticker.dart
public struct SaveImageAsSticker: Sendable {
    private let chats: ChatRepository, stickers: StickerRepository
    public init(_ chats: ChatRepository, _ stickers: StickerRepository) { self.chats = chats; self.stickers = stickers }
    public func callAsFunction(accountId: String, content: MessageContent) async -> Outcome<ChatSticker> {
        guard case .image(let img) = content else { return .failure(.unexpected("Only images can become stickers")) }
        switch await chats.loadAttachment(accountId: accountId, content: content, thumbnail: false) {
        case .success(let bytes): return await stickers.add(bytes: bytes, name: img.name.isEmpty ? "sticker.png" : img.name)
        case .failure(let f): return .failure(f)
        }
    }
}

/// The translation backend chat needs (the app adapts `FeatureTranslation`'s service to it; features never import each other).
public protocol ChatTextTranslator: Sendable {
    func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<(text: String, model: String?)>
}

/// Ported from: lib/features/chat/domain/usecases/translate_chat_message.dart
public struct TranslateChatMessage: Sendable {
    private let repository: MessageTranslationRepository, service: ChatTextTranslator
    private static let mention = RX(#"\[@([^\]]+)\]\(@#\d+\)"#)
    public init(_ repository: MessageTranslationRepository, _ service: ChatTextTranslator) { self.repository = repository; self.service = service }

    public func callAsFunction(_ message: ChatMessage, targetLang: String, model: String? = nil, force: Bool = false) async -> Outcome<ChatMessageTranslation> {
        guard case .text(let text, _) = message.content else { return .failure(.unexpected("Only text can be translated")) }
        if !force, case .success(var stored?) = await repository.find(accountId: message.accountId, gid: message.gid, targetLang: targetLang) {
            if !stored.visible { _ = await repository.setVisible(accountId: message.accountId, gid: message.gid, targetLang: targetLang, visible: true) }
            stored.visible = true
            return .success(stored)
        }
        let plain = Self.mention.replace(text) { "@\($0[1] ?? "")" }
        switch await service.translateText(key: "chat:\(message.gid)", text: plain, targetLang: targetLang, model: model) {
        case .failure(let f): return .failure(f)
        case .success(let v):
            let t = ChatMessageTranslation(accountId: message.accountId, gid: message.gid, targetLang: targetLang, text: v.text, model: v.model, createdAt: Date())
            // A failed save only costs a re-translation later; show what we have.
            _ = await repository.save(t)
            return .success(t)
        }
    }
}
