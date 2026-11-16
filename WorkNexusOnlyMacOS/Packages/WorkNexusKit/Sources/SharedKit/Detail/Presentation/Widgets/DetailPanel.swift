import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/detail_panel.dart + widgets/{detail_tab_body,translation_footer hook}
/// The ticket detail: the tool's own `buildDetail` when it has one, else header + Original / Translation tabs. A
/// workspace-coloured rule runs along the top; a thin progress bar shows while the provider refresh runs.
public struct DetailPanel: View {
    @Environment(\.appTheme) private var theme
    let controller: DetailController; let ticketId: String; var onClose: () -> Void

    public init(controller: DetailController, ticketId: String, onClose: @escaping () -> Void) {
        self.controller = controller; self.ticketId = ticketId; self.onClose = onClose
    }

    public var body: some View {
        content.task(id: "\(ticketId)|\(controller.ticket(ticketId) != nil)") { controller.ensureStarted(ticketId) }
    }

    @ViewBuilder private var content: some View {
        if let ticket = controller.ticket(ticketId) {
            let c = theme.colors
            let model = controller.model(for: ticketId)
            let ws = controller.workspace(of: ticket)
            let wsColor = ws.map { Color(argb: UInt32(truncatingIfNeeded: $0.colorValue)) } ?? c.workspaceFallback
            let layout = controller.settings.detailLayout
            Group {
                if let custom = controller.registry.module(for: ticket.providerType)?.buildDetail(ticket: ticket, onClose: onClose) {
                    custom
                } else {
                    VStack(spacing: 0) {
                        DetailHeader(controller: controller, ticket: ticket, wsColor: wsColor, model: model, onClose: onClose)
                        DetailTabBar(controller: controller, model: model)
                        ZStack(alignment: .top) {
                            DetailTabBody(controller: controller, ticket: ticket, model: model, layout: layout)
                            if model.syncing { ProgressView().progressViewStyle(.linear).tint(c.accent).frame(height: theme.borders.thick) }
                        }
                        if model.tab == .translation, let footer = controller.extensions.translationFooter?(ticket) { footer }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(c.card)
            .overlay(alignment: .top) { Rectangle().fill(wsColor).frame(height: theme.borders.heavy) }
            .overlay(alignment: .leading) { Rectangle().fill(c.line).frame(width: theme.borders.hairline) }
        }
    }
}

struct DetailTabBody: View {
    let controller: DetailController; let ticket: Ticket; let model: TicketDetailModel; let layout: DetailLayout
    var body: some View {
        switch model.tab {
        case .original: OriginalTab(controller: controller, ticket: ticket, model: model, layout: layout)
        case .translation:
            if let tab = controller.extensions.translationTab?(ticket, layout) { tab } else {
                OriginalTab(controller: controller, ticket: ticket, model: model, layout: layout)
            }
        }
    }
}
