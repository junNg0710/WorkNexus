/// Ported from: lib/features/chat/presentation/widgets/message_list_view.dart + message_list.dart (_onScrollMetrics)
import CoreUI
import SwiftUI

/// What the list reports about where it is scrolled.
struct ThreadScrollMetrics: Equatable {
    var nearTop = false
    var nearBottom = false
    /// Far enough from the newest message to show the jump-to-latest button.
    var away = false
    /// Changes as rows are added, so a first page too short to fill the screen still asks for the next one.
    var contentHeight = 0

    /// How close (in points) to either end of the loaded messages the user may scroll before the next page is fetched,
    /// so it is usually there in time.
    static let loadThreshold: CGFloat = 600
    /// Distance from the newest message that shows the jump-to-latest button.
    static let awayThreshold: CGFloat = 400

    init() {}
    init(offset: CGFloat, content: CGFloat, container: CGFloat) {
        let below = max(0, content - container - offset)
        nearTop = offset < Self.loadThreshold
        nearBottom = below < Self.loadThreshold
        away = below > Self.awayThreshold
        contentHeight = Int(content)
    }
}

/// The lazily built list of rows, oldest first, anchored to the bottom: new messages keep the newest one in view and older
/// pages added above leave the reader where they were.
struct MessageListScroll: View {
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let showSenders: Bool
    @State private var metrics = ThreadScrollMetrics()
    /// The rows (at least partly) on screen.
    @State private var visibleIds: Set<String> = []
    /// The row at the top of the viewport when older rows were asked for: put back at the top once they are in.
    @State private var restoreId: String?
    /// The list has been placed at the bottom (or at a jumped-to message): from then on its position is the reader's, so
    /// reaching the top asks for older messages. Before, the top is just where an unplaced list starts.
    @State private var positioned = false
    /// How many prepends have had the reader's place restored; loads wait for the rest.
    @State private var handledPrepends = 0
    /// Position changes made by a scroll request settle first; loads wait until then.
    @State private var quietUntil = Date.distantPast

    private static let bottomId = "#bottom"

    var body: some View {
        let model = ctx.model
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    MessageListHeaderView(reachedStart: model.reachedStart, isEmpty: model.rows.isEmpty, failed: model.loadFailed) {
                        requestOlder()
                    }
                    ForEach(model.rows) { row in
                        ThreadRowView(ctx: ctx, row: row, showSenders: showSenders).id(row.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomId)
                }
                .scrollTargetLayout()
                .padding(.vertical, theme.spacing.s16)
                // The messages span the chat's frame at any width, in line with the header and the composer: other
                // people's against its leading edge, your own against its trailing edge (bubbles keep their own cap).
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.1) { visibleIds = Set($0) }
            .onScrollGeometryChange(for: ThreadScrollMetrics.self) { g in
                ThreadScrollMetrics(offset: g.contentOffset.y + g.contentInsets.top, content: g.contentSize.height, container: g.containerSize.height)
            } action: { _, new in
                metrics = new
                model.away = new.away
                loadIfNeeded()
            }
            // While older rows are on their way, the row at the top is the one to come back to — until they arrive and
            // shift everything.
            .onChange(of: visibleIds) { _, _ in
                if model.loadingOlder, handledPrepends == model.prependCount { restoreId = topVisibleId }
            }
            .onChange(of: model.loadingOlder) { _, _ in loadIfNeeded() }
            .onChange(of: model.loadingNewer) { _, _ in loadIfNeeded() }
            // The first page is placed at the bottom; only then does the top ask for more.
            .onChange(of: model.loaded, initial: true) { _, loaded in
                guard loaded, !positioned else { return }
                quietUntil = Date().addingTimeInterval(0.5)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(550))
                    positioned = true
                    loadIfNeeded()
                }
            }
            // Older rows were added above: the reader's row goes back to the top, and no new page is asked for until it has.
            .onChange(of: model.prependCount) { _, _ in
                let id = restoreId
                restoreId = nil
                Task { @MainActor in
                    await Task.yield()
                    if let id { proxy.scrollTo(id, anchor: .top) }
                    try? await Task.sleep(for: .milliseconds(450))
                    handledPrepends = model.prependCount
                    loadIfNeeded()
                }
            }
            .onChange(of: model.scrollRequest) { _, request in
                guard let request else { return }
                scroll(request, proxy)
            }
        }
    }

    /// The first row on screen.
    private var topVisibleId: String? { ctx.model.rows.first { visibleIds.contains($0.id) }?.id }

    private func requestOlder() {
        guard !ctx.model.loadingOlder else { return }
        restoreId = topVisibleId
        ctx.model.beginLoadOlder()
    }

    /// Fetches the next older page near the top — and, in a window jumped to far back, the next newer one near the bottom.
    private func loadIfNeeded() {
        let model = ctx.model
        guard positioned, Date() >= quietUntil, handledPrepends == model.prependCount else { return }
        if metrics.nearTop, model.canAutoLoadOlder { requestOlder() }
        if metrics.nearBottom, model.canAutoLoadNewer { model.beginLoadNewer() }
    }

    private func scroll(_ request: ChatScrollRequest, _ proxy: ScrollViewProxy) {
        positioned = true
        quietUntil = Date().addingTimeInterval(0.8)
        restoreId = nil
        Task { @MainActor in
            // After the rows of a new window are laid out.
            try? await Task.sleep(for: .milliseconds(40))
            let go = {
                switch request.target {
                case .bottom: proxy.scrollTo(Self.bottomId, anchor: .bottom)
                case .message(let gid): proxy.scrollTo(gid, anchor: .center)
                }
            }
            if request.animated { withAnimation(.easeOut(duration: theme.motion.slow), go) } else { go() }
            // Rows around a jumped-to message are still being measured (names, images, cards that load): put it back.
            if case .message = request.target {
                try? await Task.sleep(for: .milliseconds(250))
                go()
            }
        }
    }
}
