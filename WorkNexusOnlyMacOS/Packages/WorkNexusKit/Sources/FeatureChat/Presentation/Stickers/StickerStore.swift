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
    /// The stickers sent lately (`ChatSticker.recentKey`), newest first.
    private(set) var recentKeys: [String] = []
    private let repository: StickerRepository
    @ObservationIgnored private var saving: Task<Void, Never>?
    /// The "set" the bar shows the recently sent stickers under (no real set has this id).
    static let recentPack = "#recent"

    init(_ repository: StickerRepository) { self.repository = repository }

    func reload() async {
        switch await repository.stickers() {
        case .success(let all): phase = .ready(all)
        case .failure(let f): phase = .failed(f.message)
        }
        lastPack = (await repository.lastPack()).value ?? nil
        recentKeys = (await repository.recentStickers()).value ?? []
    }

    /// A sticker was sent: it leads the recent ones from now on.
    func noteSent(_ sticker: ChatSticker) {
        let next = RecentStickers().adding(sticker, to: recentKeys)
        guard next != recentKeys else { return }
        recentKeys = next
        // One write after the other: two stickers sent in a row must not leave the older list on disk.
        let earlier = saving
        saving = Task { [repository] in
            await earlier?.value
            _ = await repository.rememberRecentStickers(next)
        }
    }

    /// The recently sent stickers that still exist, newest first.
    func recents(in all: [ChatSticker]) -> [ChatSticker] { RecentStickers().resolve(recentKeys, in: all) }

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
