/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_reader_controller.dart
import Foundation
import Observation
import SwiftUI

/// Where the page should scroll: the top-level block `block`, shown at `anchor`. `token` makes two requests for the
/// same block distinct, so asking again scrolls again.
public struct ZentaoScrollRequest: Equatable, Sendable {
    public var block: Int
    public var anchor: UnitPoint
    public var token: Int
}

/// The open document's reading state shared by its page, find bar and outline: which find match is current, which
/// heading is being read, and what the page should scroll to.
@MainActor @Observable
public final class ZentaoDocReader {
    /// The find match on show, or -1 without matches.
    public private(set) var current = -1
    /// How many matches the search marked.
    public private(set) var total = 0
    /// The heading the reader is in (the last one scrolled past), or -1.
    public private(set) var activeHeading = -1
    public private(set) var scrollRequest: ZentaoScrollRequest?

    /// Page layout of the prepared body: which block each heading / match sits in.
    @ObservationIgnored public var layout = ZentaoDocLayout([])
    /// Top of each heading's block from the top of the page's viewport, as last measured.
    @ObservationIgnored var headingTops: [Int: CGFloat] = [:]
    @ObservationIgnored var viewportHeight: CGFloat = 0
    @ObservationIgnored var atEnd = false
    /// Counts trips to a heading picked from the outline; `goingToHeading` holds while the latest one is under way.
    /// The outline lights the picked heading at once, and the sections the page scrolls past on the way must not
    /// each light up in turn.
    @ObservationIgnored private var trip = 0
    @ObservationIgnored private var goingToHeading = false
    @ObservationIgnored private var tokens = 0

    /// How long the scroll to a picked heading is held against tracking (it may cross many screens).
    public static let headingTrip: Duration = .milliseconds(450)

    public init() {}

    public var matchCount: Int { total }

    /// A new search marked `count` matches: the first becomes current.
    public func resetMatches(_ count: Int) {
        total = count
        current = count > 0 ? 0 : -1
    }

    public func next() { step(1) }
    public func previous() { step(-1) }

    private func step(_ by: Int) {
        guard total > 0 else { return }
        current = ((current + by) % total + total) % total
        revealCurrent()
    }

    /// Scrolls the current match into view (a third down the page).
    public func revealCurrent() {
        guard current >= 0, let block = layout.blockOfMatch[current] else { return }
        request(block, anchor: UnitPoint(x: 0.5, y: 0.35))
    }

    /// Scrolls heading `index` to the top of the page, and lights it in the outline at once.
    public func goToHeading(_ index: Int) {
        activeHeading = index
        guard let block = layout.blockOfHeading[index] else { return }
        trip += 1
        let mine = trip
        goingToHeading = true
        request(block, anchor: .top)
        Task { [weak self] in
            try? await Task.sleep(for: Self.headingTrip)
            guard let self, mine == self.trip else { return }
            goingToHeading = false
            activeHeading = index
        }
    }

    private func request(_ block: Int, anchor: UnitPoint) {
        tokens += 1
        scrollRequest = ZentaoScrollRequest(block: block, anchor: anchor, token: tokens)
    }

    /// The page measured its headings (`tops`, from the viewport's top) or its viewport.
    public func track(tops: [Int: CGFloat]? = nil, viewportHeight: CGFloat? = nil, atEnd: Bool? = nil, lead: CGFloat) {
        if let tops { headingTops = tops }
        if let viewportHeight { self.viewportHeight = viewportHeight }
        if let atEnd { self.atEnd = atEnd }
        guard !goingToHeading else { return }
        let active = Self.activeHeading(tops: headingTops, lead: lead, atEnd: self.atEnd, viewportHeight: self.viewportHeight)
        if active != activeHeading { activeHeading = active }
    }

    /// The heading being read: the last one at or above `lead` points from the top of the viewport - or, at the very
    /// end of the page, the last one on screen, so the closing sections can become active too. The first heading
    /// stands in while none has been reached; -1 without headings.
    public nonisolated static func activeHeading(tops: [Int: CGFloat], lead: CGFloat, atEnd: Bool,
                                                  viewportHeight: CGFloat) -> Int {
        var active = -1
        for index in tops.keys.sorted() {
            let y = tops[index]!
            if y <= lead || (atEnd && y < viewportHeight) { active = index }
        }
        if active < 0, let first = tops.keys.min() { active = first }
        return active
    }
}
