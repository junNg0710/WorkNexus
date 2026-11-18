/// Ported from: lib/features/chat/presentation/widgets/message_list_view.dart + message_list.dart (_onScrollMetrics)
import CoreDomain
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
    /// While the chat opens, only the newest rows are built at first (see `ChatOpeningStage`).
    var stage = ChatOpeningStage.all
    /// Where the list is scrolled. Like `visible`, read only by the load checks, never drawn: as state it redrew the list
    /// whenever the content height changed, which it does as rows scroll in and get measured.
    @State private var scrolled = ScrollMemo()
    /// Whether the list is scrolling, for the rows to read when the pointer comes over them (never drawn).
    @State private var activity = ChatScrollActivity()
    /// The rows (at least partly) on screen. Kept outside SwiftUI's state: it changes as every row scrolls in or out, and as
    /// state it re-ran this view - and every row of the list - on each change, which made scrolling stutter.
    @State private var visible = VisibleRows()
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
                    if stage == .all {
                        MessageListHeaderView(reachedStart: model.reachedStart, isEmpty: model.rows.isEmpty, failed: model.loadFailed) {
                            requestOlder()
                        }
                    }
                    ForEach(stage.shown(model.rows)) { row in
                        ThreadRowView(ctx: ctx, row: row, showSenders: showSenders).equatable().id(row.id)
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
            .onScrollPhaseChange { _, phase in activity.isScrolling = phase.isScrolling }
            .environment(\.chatScrollActivity, activity)
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.1) { ids in
                visible.ids = Set(ids)
                if PerformanceLog.isEnabled { PerformanceLog.setContext("chat", ChatRowsOnScreen.describe(model.rows, visible: visible.ids)) }
                // While older rows are on their way, the row at the top is the one to come back to - until they arrive.
                if model.loadingOlder, handledPrepends == model.prependCount { restoreId = topVisibleId }
            }
            .onScrollGeometryChange(for: ThreadScrollMetrics.self) { g in
                ThreadScrollMetrics(offset: g.contentOffset.y + g.contentInsets.top, content: g.contentSize.height, container: g.containerSize.height)
            } action: { _, new in
                scrolled.metrics = new
                if model.away != new.away { model.away = new.away }
                loadIfNeeded()
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
            .onDisappear { PerformanceLog.setContext("chat", nil) }
            // `initial`: a request made before the rows came in (a jump while the chat was opening) is taken when they do.
            .onChange(of: model.scrollRequest, initial: true) { _, request in
                guard let request else { return }
                scroll(request, proxy)
            }
        }
    }

    /// The first row on screen.
    private var topVisibleId: String? { ctx.model.rows.first { visible.ids.contains($0.id) }?.id }

    private func requestOlder() {
        guard !ctx.model.loadingOlder else { return }
        restoreId = topVisibleId
        ctx.model.beginLoadOlder()
    }

    /// Fetches the next older page near the top — and, in a window jumped to far back, the next newer one near the bottom.
    private func loadIfNeeded() {
        let model = ctx.model
        guard positioned, Date() >= quietUntil, handledPrepends == model.prependCount else { return }
        if scrolled.metrics.nearTop, model.canAutoLoadOlder { requestOlder() }
        if scrolled.metrics.nearBottom, model.canAutoLoadNewer { model.beginLoadNewer() }
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

/// The ids of the rows on screen, in a plain reference so changing them does not redraw the list.
final class VisibleRows { var ids: Set<String> = [] }

/// What the performance log says about the chat rows on screen when it notes a stutter: how many, and how many of the
/// kinds that cost the most to draw.
enum ChatRowsOnScreen {
    static func describe(_ rows: [ChatListRow], visible: Set<String>) -> String {
        var count = 0, pictures = 0, stickers = 0, videos = 0, files = 0, links = 0, long = 0, code = 0
        for row in rows where visible.contains(row.id) {
            count += 1
            guard case .message(let m) = row.item else { continue }
            switch m.content {
            case .image(let i): if IsStickerImage()(i) { stickers += 1 } else { pictures += 1 }
            case .file(let f): if isVideoFile(f) { videos += 1 } else { files += 1 }
            case .text(let t, _):
                if t.contains("http://") || t.contains("https://") { links += 1 }
                if t.count > 400 { long += 1 }
            case .code: code += 1
            default: break
            }
        }
        let kinds = [("pictures", pictures), ("stickers", stickers), ("videos", videos), ("files", files), ("links", links),
                     ("long texts", long), ("code", code)].filter { $0.1 > 0 }.map { "\($0.1) \($0.0)" }
        return "\(count) chat rows on screen" + (kinds.isEmpty ? "" : " (" + kinds.joined(separator: ", ") + ")")
    }
}

/// Whether the message list is scrolling, in a plain reference: rows read it in their hover handler, so a scroll starting
/// or stopping redraws nothing.
final class ChatScrollActivity { var isScrolling = false }

private struct ChatScrollActivityKey: EnvironmentKey { static let defaultValue: ChatScrollActivity? = nil }
extension EnvironmentValues {
    var chatScrollActivity: ChatScrollActivity? {
        get { self[ChatScrollActivityKey.self] }
        set { self[ChatScrollActivityKey.self] = newValue }
    }
}

/// The latest scroll metrics, in a plain reference so updating them does not redraw the list.
final class ScrollMemo { var metrics = ThreadScrollMetrics() }
