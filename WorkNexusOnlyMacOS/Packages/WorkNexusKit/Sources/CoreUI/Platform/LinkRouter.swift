import Foundation

/// Ported from: lib/core/platform/link_router.dart
/// Where a tapped web link may be taken before it falls through to the browser, in the order they are tried.
public enum LinkStage: Int, CaseIterable, Sendable {
    /// Something the app shows itself (a ZenTao ticket in the detail panel).
    case app
    /// A mini app for the link's site.
    case miniApp
}

/// One step of the chain: opens `url` itself and says so, or declines so the next step is tried.
@MainActor
public protocol LinkHandler: AnyObject {
    func handle(_ url: String) -> Bool
}

/// Chain of responsibility for a tapped web link. Features register a handler for their `LinkStage`; the router asks
/// them in stage order until one opens the link. The browser is not a stage: it is where a link ends up when `route`
/// returns false.
@MainActor
public final class LinkRouter {
    public static let shared = LinkRouter()
    private var handlers: [LinkStage: LinkHandler] = [:]
    public init() {}

    /// Makes `handler` the one for `stage`, replacing an earlier one.
    public func register(_ stage: LinkStage, _ handler: LinkHandler) { handlers[stage] = handler }

    /// Removes `handler` from `stage` — only if it is still the one there, so a late teardown cannot remove its replacement.
    public func unregister(_ stage: LinkStage, _ handler: LinkHandler) {
        if handlers[stage] === handler { handlers[stage] = nil }
    }

    /// Whether a handler opened `url`. Stages in `skip` are not asked.
    public func route(_ url: String, skip: Set<LinkStage> = []) -> Bool {
        for stage in LinkStage.allCases where !skip.contains(stage) {
            if handlers[stage]?.handle(url) == true { return true }
        }
        return false
    }
}
