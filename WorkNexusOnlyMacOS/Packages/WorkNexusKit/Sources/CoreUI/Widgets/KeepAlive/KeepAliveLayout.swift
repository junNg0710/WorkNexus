import SwiftUI

/// What `KeepAliveLayout` needs to know about each place it lays out.
public struct KeepAlivePlace: Equatable, Sendable {
    public var key = ""
    public var active = true
    public init(key: String = "", active: Bool = true) { self.key = key; self.active = active }
}

private struct KeepAlivePlaceKey: LayoutValueKey { static let defaultValue = KeepAlivePlace() }

public extension View {
    /// Names a place for `KeepAliveLayout` and says whether it is the one on screen.
    func keepAlivePlace(_ key: String, active: Bool) -> some View {
        layoutValue(key: KeepAlivePlaceKey.self, value: KeepAlivePlace(key: key, active: active))
    }
}

/// Views kept mounted (the shell's places, the chats last opened), one over the other, each as large as the stack - but
/// only the one on screen follows the stack's size. A hidden place keeps the size it last had on screen, so a change of the stack's width (the tool pane
/// coming and going between Chat and a board, a window resize) does not lay a hidden chat or board out again: before, every
/// trip between Chat and Tasks wrapped all the messages of the hidden chat twice. It never asks a place for its size or
/// its alignment guides either (a `ZStack` asks every child for both whenever it is measured).
public struct KeepAliveLayout: Layout {
    public struct Cache {
        var sizes: [String: CGSize] = [:]
    }

    public init() {}

    public func makeCache(subviews: Subviews) -> Cache { Cache() }

    /// Keeps the sizes of the places still mounted (the default starts over, forgetting them on every switch).
    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        let mounted = Set(subviews.map { $0[KeepAlivePlaceKey.self].key })
        cache.sizes = cache.sizes.filter { mounted.contains($0.key) }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        for subview in subviews {
            let place = subview[KeepAlivePlaceKey.self]
            let size = Self.size(of: place, in: bounds.size, last: cache.sizes[place.key])
            if place.active { cache.sizes[place.key] = size }
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }

    // No guides of its own: the default merges those of every place, which lays each of them out to ask (a `ZStack`
    // around this one asks whenever it is measured).
    public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                           cache: inout Cache) -> CGFloat? { nil }
    public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                           cache: inout Cache) -> CGFloat? { nil }

    /// The size a place is given: the stack's own while it is on screen, otherwise the one it last had there (`last`), and
    /// the stack's own for a place that was never on screen.
    public static func size(of place: KeepAlivePlace, in stack: CGSize, last: CGSize?) -> CGSize {
        place.active ? stack : (last ?? stack)
    }
}
