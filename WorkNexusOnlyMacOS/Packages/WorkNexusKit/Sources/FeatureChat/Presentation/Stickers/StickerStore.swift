/// Ported from: lib/features/chat/presentation/providers/sticker_providers.dart (`chatStickersProvider`, `StickerController`)
import CoreDomain
import Foundation
import Observation

/// The user's stickers (bundled + imported + their own), loaded through the `StickerRepository`.
@MainActor @Observable
final class StickerStore {
    enum Phase { case loading, ready([ChatSticker]), failed(String) }
    private(set) var phase = Phase.loading
    private(set) var lastPack: String?
    private let repository: StickerRepository

    init(_ repository: StickerRepository) { self.repository = repository }

    func reload() async {
        switch await repository.stickers() {
        case .success(let all): phase = .ready(all)
        case .failure(let f): phase = .failed(f.message)
        }
        lastPack = (await repository.lastPack()).value ?? nil
    }

    func remember(_ pack: String) {
        guard lastPack != pack else { return }
        lastPack = pack
        Task { _ = await repository.rememberPack(pack) }
    }

    func removePack(_ pack: String) async -> Outcome<Void> { await changed(await repository.removePack(pack)) }
    func remove(_ sticker: ChatSticker) async -> Outcome<Void> { await changed(await repository.remove(sticker)) }

    func add(bytes: Data, name: String) async -> Outcome<Void> {
        switch await repository.add(bytes: bytes, name: name) {
        case .success: await reload(); return .success(())
        case .failure(let f): return .failure(f)
        }
    }

    private func changed(_ r: Outcome<Void>) async -> Outcome<Void> {
        if case .success = r { await reload() }
        return r
    }
}
