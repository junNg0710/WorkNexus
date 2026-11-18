import CoreDomain
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let imageExtensions: Set<String> = ["png", "gif", "webp", "jpg", "jpeg", "heic", "bmp"]
private func isImagePath(_ p: String) -> Bool { imageExtensions.contains((p as NSString).pathExtension.lowercased()) }
private func safeName(_ n: String) -> String { String(n.unicodeScalars.map { $0.properties.isAlphabetic || ("0123456789_.-".unicodeScalars.contains($0)) ? Character($0) : "_" }) }

/// Stickers: bundled sets (`<bundleRoot>/<pack>/<file>`, each tagged by its `stickers.json`), imported packs
/// (`<dir>/packs/<pack>/` + `pack.json` with its id, title and each sticker's emoji) and the user's own files.
/// Ported from: lib/features/chat/data/repositories/local_sticker_repository.dart
final class LocalStickerRepository: StickerRepository, @unchecked Sendable {
    private let bundleRoot: URL?
    private let directory: URL
    private let converter: StickerConverter?
    private static let packMeta = "pack.json", lastPackName = "last_pack", recentName = "recent_stickers.json"
    /// A bundled set's tags, beside its images.
    private static let tagsFile = "stickers.json"
    private var fm: FileManager { .default }

    init(bundleRoot: URL?, directory: URL, converter: StickerConverter? = nil) {
        self.bundleRoot = bundleRoot; self.directory = directory; self.converter = converter
    }

    private func list(_ dir: URL) -> [URL] { (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] }
    private var packsDir: URL { directory.appendingPathComponent("packs", isDirectory: true) }
    private func packDir(_ pack: String) -> URL { packsDir.appendingPathComponent(safeName(pack), isDirectory: true) }

    func stickers() async -> Outcome<[ChatSticker]> { .success(bundled() + imported() + custom()) }

    private func bundled() -> [ChatSticker] {
        guard let root = bundleRoot else { return [] }
        var out: [ChatSticker] = []
        for folder in list(root).filter({ $0.hasDirectoryPath }).sorted(by: { $0.path < $1.path }) {
            let tags = Self.tags(of: folder.appendingPathComponent(Self.tagsFile))
            for f in list(folder).filter({ isImagePath($0.path) }).sorted(by: { $0.path < $1.path }) {
                let tag = tags[f.lastPathComponent]
                out.append(ChatSticker(id: f.path, pack: folder.lastPathComponent, name: f.lastPathComponent, location: f.path,
                                       emoji: tag?.emoji ?? "", keywords: tag?.keywords ?? []))
            }
        }
        return out
    }

    /// A set's tags by file name. Each is the emoji a sticker stands for (`"001.webp": "😂🤣"`) or, with words to suggest it
    /// for too, `{"emoji": "🙏", "keywords": ["cam on", "thanks"]}`. A missing or unreadable file tags nothing.
    static func tags(of file: URL) -> [String: (emoji: String, keywords: [String])] {
        guard let data = try? Data(contentsOf: file), let json = try? JSONValue.parse(data: data), case .object(let entries) = json else { return [:] }
        var out: [String: (emoji: String, keywords: [String])] = [:]
        for (name, value) in entries.pairs {
            if let emoji = value.string { out[name] = (emoji, []); continue }
            guard let emoji = value["emoji"]?.string else { continue }
            out[name] = (emoji, value["keywords"]?.array?.compactMap(\.string) ?? [])
        }
        return out
    }

    private func imported() -> [ChatSticker] {
        list(packsDir).filter { $0.hasDirectoryPath && !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.path < $1.path }.flatMap { folder -> [ChatSticker] in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.packMeta)), let meta = try? JSONValue.parse(data: data),
                  let pack = meta["id"]?.string else { return [] }
            let title = meta["title"]?.string ?? pack
            let emoji = meta["emoji"]
            return list(folder).filter { isImagePath($0.path) }.sorted { $0.path < $1.path }.map {
                ChatSticker(id: $0.path, pack: pack, packTitle: title, name: $0.lastPathComponent, location: $0.path, custom: true,
                            emoji: emoji?[$0.lastPathComponent]?.string ?? "")
            }
        }
    }

    private func custom() -> [ChatSticker] {
        list(directory).filter { !$0.hasDirectoryPath && isImagePath($0.path) }.sorted { $0.path > $1.path }.map(customSticker)
    }

    private func customSticker(_ f: URL) -> ChatSticker {
        let base = f.lastPathComponent
        let name = base.firstIndex(of: "_").map { String(base[base.index(after: $0)...]) } ?? base
        return ChatSticker(id: f.path, pack: "", name: name, location: f.path, custom: true)
    }

    func bytes(_ sticker: ChatSticker) async -> Outcome<Data> {
        do { return .success(try Data(contentsOf: URL(fileURLWithPath: sticker.location))) }
        catch { return .failure(.storage("Could not read the sticker: \(error.localizedDescription)")) }
    }

    func add(bytes: Data, name: String) async -> Outcome<ChatSticker> {
        guard !bytes.isEmpty else { return .failure(.unexpected("Cannot keep an empty sticker")) }
        var data = bytes, fileName = name
        // An animated image (a GIF, an animated WebP) is kept as it came: fitting it would keep one frame.
        let frames = CGImageSourceCreateWithData(bytes as CFData, nil).map(CGImageSourceGetCount) ?? 0
        // An image that cannot be fitted is still worth keeping as it came.
        if frames <= 1, let fitted = await converter?.imageToWebp(image: bytes).value {
            data = fitted
            fileName = ((name as NSString).deletingPathExtension) + ".png"
        }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let safe = safeName(fileName)
            let file = directory.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))_\(isImagePath(safe) ? safe : safe + ".png")")
            try data.write(to: file, options: .atomic)
            return .success(customSticker(file))
        } catch { return .failure(.storage("Could not keep the sticker: \(error.localizedDescription)")) }
    }

    func remove(_ sticker: ChatSticker) async -> Outcome<Void> {
        guard sticker.custom else { return .failure(.unexpected("Bundled stickers stay")) }
        try? fm.removeItem(atPath: sticker.location)
        return .success(())
    }

    func addPack(_ pack: String, title: String, stickers: [StickerFile]) async -> Outcome<Void> {
        guard !stickers.isEmpty else { return .failure(.unexpected("Cannot keep an empty set")) }
        let target = packDir(pack)
        let staging = packsDir.appendingPathComponent(".\(target.lastPathComponent).tmp", isDirectory: true)
        do {
            // Written beside the set first, so a failed write never leaves a half set (or loses the one it replaces).
            try? fm.removeItem(at: staging)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            var emoji: [(String, JSONValue)] = []
            for s in stickers {
                let safe = safeName(s.name)
                try s.bytes.write(to: staging.appendingPathComponent(safe))
                if !s.emoji.isEmpty { emoji.append((safe, .string(s.emoji))) }
            }
            let meta = JSONValue.object(JSONObject([("id", .string(pack)), ("title", .string(title)), ("emoji", .object(JSONObject(emoji)))]))
            try Data(meta.serialized().utf8).write(to: staging.appendingPathComponent(Self.packMeta))
            try? fm.removeItem(at: target)
            try fm.moveItem(at: staging, to: target)
            return .success(())
        } catch { return .failure(.storage("Could not keep the sticker set: \(error.localizedDescription)")) }
    }

    func removePack(_ pack: String) async -> Outcome<Void> { try? fm.removeItem(at: packDir(pack)); return .success(()) }

    func lastPack() async -> Outcome<String?> { .success(try? String(contentsOf: directory.appendingPathComponent(Self.lastPackName), encoding: .utf8)) }

    func rememberPack(_ pack: String) async -> Outcome<Void> {
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try pack.write(to: directory.appendingPathComponent(Self.lastPackName), atomically: true, encoding: .utf8)
            return .success(())
        } catch { return .failure(.storage("Could not keep the last sticker set: \(error.localizedDescription)")) }
    }

    func recentStickers() async -> Outcome<[String]> {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(Self.recentName)) else { return .success([]) }
        return .success((try? JSONDecoder().decode([String].self, from: data)) ?? [])
    }

    func rememberRecentStickers(_ keys: [String]) async -> Outcome<Void> {
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(keys).write(to: directory.appendingPathComponent(Self.recentName), options: .atomic)
            return .success(())
        } catch { return .failure(.storage("Could not keep the recent stickers: \(error.localizedDescription)")) }
    }
}

/// Ported from: lib/features/chat/data/repositories/local_wallpaper_repository.dart
final class LocalWallpaperRepository: WallpaperRepository, @unchecked Sendable {
    private let directory: URL
    init(directory: URL) { self.directory = directory }

    func wallpapers() async -> Outcome<[String]> {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return .success(files.map(\.path).filter(isImagePath).sorted(by: >))
    }

    func add(bytes: Data, name: String) async -> Outcome<String> {
        guard !bytes.isEmpty else { return .failure(.unexpected("Cannot use an empty image")) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safe = safeName(name)
            let file = directory.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))_\(isImagePath(safe) ? safe : safe + ".png")")
            try bytes.write(to: file, options: .atomic)
            return .success(file.path)
        } catch { return .failure(.storage("Could not keep the wallpaper: \(error.localizedDescription)")) }
    }

    func remove(path: String) async -> Outcome<Void> {
        let file = URL(fileURLWithPath: path)
        // Only files this repository keeps.
        guard file.deletingLastPathComponent().resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path else { return .failure(.unexpected("Not a saved wallpaper")) }
        try? FileManager.default.removeItem(at: file)
        return .success(())
    }
}

/// Scales a picture down to a 128 px still (PNG). Animated `.tgs` stickers are not converted: `ImportStickerPack` then
/// falls back to the set's still thumbnail (the Dart client rendered Lottie frames to animated WebP).
/// Ported from: lib/features/chat/data/datasources/webp_sticker_converter.dart
struct ImageStickerConverter: StickerConverter {
    var size = 128
    func animatedToWebp(tgs: Data) async -> Outcome<Data> { .failure(.parse("Animated stickers are imported as stills")) }

    func imageToWebp(image: Data) async -> Outcome<Data> {
        guard let src = CGImageSourceCreateWithData(image as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                                                       kCGImageSourceThumbnailMaxPixelSize: size] as CFDictionary) else { return .failure(.parse("A sticker image could not be read")) }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return .failure(.parse("A sticker image could not be read")) }
        CGImageDestinationAddImage(dest, thumb, nil)
        return CGImageDestinationFinalize(dest) ? .success(out as Data) : .failure(.parse("A sticker image could not be read"))
    }
}

/// Telegram Bot API access for sticker import (the token is never logged or put in a failure).
/// Ported from: lib/features/chat/data/datasources/telegram_sticker_source.dart
struct TelegramStickerSource: StickerPackSource {
    private static let api = "https://api.telegram.org"

    func stickerSet(name: String, token: String) async -> Outcome<RemoteStickerSet> {
        switch await call(token, "getStickerSet", ["name": name]) {
        case .failure(let f): return .failure(f)
        case .success(let json):
            guard let n = json["name"]?.string, let list = json["stickers"]?.array else { return .failure(.parse("Telegram sent an unreadable sticker set")) }
            let stickers: [RemoteSticker] = list.compactMap { s in
                guard let id = s["file_id"]?.string else { return nil }
                let thumb = (s["thumbnail"] ?? s["thumb"])?["file_id"]?.string
                return RemoteSticker(fileId: id, kind: s["is_video"] == .bool(true) ? .video : s["is_animated"] == .bool(true) ? .animated : .still,
                                     thumbnailFileId: thumb, emoji: s["emoji"]?.string ?? "")
            }
            return .success(RemoteStickerSet(name: n, title: json["title"]?.string ?? n, stickers: stickers))
        }
    }

    func file(fileId: String, token: String) async -> Outcome<Data> {
        switch await call(token, "getFile", ["file_id": fileId]) {
        case .failure(let f): return .failure(f)
        case .success(let info):
            guard let path = info["file_path"]?.string, let url = URL(string: "\(Self.api)/file/bot\(token)/\(path)") else { return .failure(.notFound("Telegram gave no file for a sticker")) }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                guard (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return .failure(.notFound("A sticker file could not be fetched")) }
                return .success(data)
            } catch { return .failure(.network("Telegram could not be reached")) }   // never the error: its URL holds the token
        }
    }

    private func call(_ token: String, _ method: String, _ params: [String: String]) async -> Outcome<JSONValue> {
        var c = URLComponents(string: "\(Self.api)/bot\(token)/\(method)")!
        c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        do {
            let (data, resp) = try await URLSession.shared.data(from: c.url!)
            guard let json = try? JSONValue.parse(data: data) else { return .failure(.parse("Telegram sent something unreadable")) }
            if json["ok"] == .bool(true), let result = json["result"] { return .success(result) }
            let reason = json["description"]?.string ?? "Telegram refused"
            switch (resp as? HTTPURLResponse)?.statusCode {
            case 401: return .failure(.auth("The Telegram bot token was refused: \(reason)"))
            case 400 where reason.contains("STICKERSET_INVALID"): return .failure(.notFound("No sticker set has this link: \(reason)"))
            default: return .failure(.unexpected(reason))
            }
        } catch { return .failure(.network("Telegram could not be reached")) }
    }
}

/// The Telegram bot token lives in the shared credential store (Keychain).
/// Ported from: lib/features/chat/data/repositories/keychain_telegram_token_store.dart
struct CredentialTelegramTokenStore: TelegramTokenStore {
    static let key = "chat:telegram-token"
    let store: CredentialStore
    func read() async -> String? { await store.read(Self.key) }
    func write(_ token: String) async { _ = await store.write(Self.key, value: token) }
}
