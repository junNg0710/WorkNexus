import CoreUI
import SwiftUI

/// Ported from: lib/features/notifications/presentation/widgets/notifications_panel.dart
/// ZenTao's web notifications (the bell menu) in a panel sliding out beside the rail, over the current view, while
/// `model.panelOpen`. It sits under the detail slide-over, so a ticket opened from it shows on the right with the list
/// still in place. Escape, the bell or a click outside closes it. Host it in an overlay of the shell's content.
public struct NotificationsPanel: View {
    @Environment(\.appTheme) private var theme
    private let model: NotificationsModel
    private let leftInset: CGFloat
    private let dateFormat: String

    /// - Parameters: `leftInset` is where the panel starts (right of the rail, which stays usable); `dateFormat` is
    ///   `AppSettings.dateFormat` for day headings older than yesterday.
    public init(model: NotificationsModel, leftInset: CGFloat = 0, dateFormat: String = "iso") {
        self.model = model; self.leftInset = leftInset; self.dateFormat = dateFormat
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            if model.panelOpen {
                theme.colors.scrim.opacity(Self.scrimAlpha).contentShape(Rectangle()).onTapGesture { model.closePanel() }
                    .transition(.opacity)
                NotificationsPanelBody(model: model, dateFormat: dateFormat)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.leading, leftInset)
        .animation(.easeOut(duration: theme.motion.slow), value: model.panelOpen)
    }

    /// Dims what the panel covers; a tap on it closes the panel.
    static let scrimAlpha = 0.12
}

private struct NotificationsPanelBody: View {
    @Environment(\.appTheme) private var theme
    let model: NotificationsModel
    let dateFormat: String

    var body: some View {
        let days = model.days
        VStack(spacing: 0) {
            NotificationsHeader(model: model)
            if model.refreshFailed && !days.isEmpty {
                AppInlineNote(NotificationStrings.refreshFailed, isError: true)
                    .padding(EdgeInsets(top: theme.spacing.s12, leading: theme.spacing.s20, bottom: 0, trailing: theme.spacing.s20))
            }
            content(days)
        }
        .frame(width: 400).frame(maxHeight: .infinity)
        .background(theme.colors.bg)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.colors.line).frame(width: theme.borders.hairline) }
        .shadow(color: theme.colors.scrim.opacity(NotificationsPanel.scrimAlpha), radius: theme.spacing.s40)
        .onKeyPress(.escape) { model.closePanel(); return .handled }
    }

    @ViewBuilder private func content(_ days: [NotificationDay]) -> some View {
        if !days.isEmpty { NotificationDayList(days: days, model: model, dateFormat: dateFormat) }
        else if model.isRefreshing || !model.hasLoaded { AppStateView(.loading) }
        else if model.refreshFailed { AppStateView(.error(NotificationStrings.loadFailed)) { Task { await model.refresh() } } }
        else { AppStateView(.empty(model.unreadOnly ? NotificationStrings.emptyUnread : NotificationStrings.empty)) }
    }
}
