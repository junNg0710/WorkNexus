import Foundation
import Observation

/// One button of the rail's own apps: a website or a Mac app.
public enum RailAppItem: Identifiable, Equatable, Sendable {
    case miniApp(MiniAppRailItem)
    case nativeApp(NativeAppRailItem)

    public var ref: RailAppRef {
        switch self {
        case .miniApp(let item): .miniApp(item.id)
        case .nativeApp(let item): .nativeApp(item.id)
        }
    }

    /// The id of its place on the rail (`RailAppRef.id`).
    public var id: String { ref.id }

    public var name: String {
        switch self {
        case .miniApp(let item): item.name
        case .nativeApp(let item): item.name
        }
    }
}

/// Not in the Flutter app. The websites and the Mac apps the user added, as the one list the rail shows: any of them can
/// sit anywhere among the others. Moving one - a step up or down, or dropped on another - keeps the new order for both
/// kinds at once.
@MainActor @Observable
public final class RailAppsModel {
    public let miniApps: MiniAppsModel
    public let nativeApps: NativeAppsModel
    private let moveApp: MoveRailApp

    init(miniApps: MiniAppsModel, nativeApps: NativeAppsModel, move: MoveRailApp) {
        self.miniApps = miniApps; self.nativeApps = nativeApps; moveApp = move
    }

    /// Every website and Mac app, in rail order.
    public var order: [RailAppRef] { OrderRailApps()(miniApps: miniApps.apps, nativeApps: nativeApps.apps) }

    /// The rail's buttons, in rail order.
    public var items: [RailAppItem] {
        let websites = Dictionary(miniApps.railItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let macApps = Dictionary(nativeApps.railItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { ref in
            switch ref.kind {
            case .miniApp: websites[ref.appId].map(RailAppItem.miniApp)
            case .nativeApp: macApps[ref.appId].map(RailAppItem.nativeApp)
            }
        }
    }

    public func canMove(_ ref: RailAppRef, by step: Int) -> Bool {
        let order = order
        guard let i = order.firstIndex(of: ref) else { return false }
        return order.indices.contains(i + step)
    }

    /// One step towards the start (-1) or the end (+1) of the rail, past whatever is there: a website or a Mac app.
    public func move(_ ref: RailAppRef, by step: Int) async {
        let order = order
        guard let from = order.firstIndex(of: ref) else { return }
        await move(order, from: from, to: from + step)
    }

    /// Drops `ref` where `target` is on the rail (a drag and drop): it takes `target`'s place and the rest shift.
    public func move(_ ref: RailAppRef, onto target: RailAppRef) async {
        let order = order
        guard let from = order.firstIndex(of: ref), let to = order.firstIndex(of: target) else { return }
        await move(order, from: from, to: to)
    }

    /// What a drag of a rail button carries (`RailAppRef.id`) was dropped on `target`. False when it is not one of the
    /// rail's own apps (some other text), or is `target` itself.
    public func drop(_ payload: String?, onto target: RailAppRef) -> Bool {
        guard let ref = payload.flatMap(RailAppRef.init(placeId:)), ref != target, order.contains(ref) else { return false }
        Task { await move(ref, onto: target) }
        return true
    }

    private func move(_ order: [RailAppRef], from: Int, to: Int) async {
        guard case .success(let moved) = await moveApp(order, from: from, to: to), moved != order else { return }
        // Shown at once: the database's own word follows.
        let positions = Dictionary(moved.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        miniApps.reposition { positions[.miniApp($0)] }
        nativeApps.reposition { positions[.nativeApp($0)] }
    }
}
