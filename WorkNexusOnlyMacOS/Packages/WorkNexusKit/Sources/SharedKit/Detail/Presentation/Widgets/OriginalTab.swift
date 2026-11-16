import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{original_tab,item_description}.dart
/// The Original tab: the tool's effort / subtasks / attachments blocks around the description (HTML or Markdown as
/// the provider wrote it, images through the authenticated loader), labels, the activity timeline, and the sidebar
/// (the tool's, else a generic "Details" card).
public struct OriginalTab: View {
    @Environment(\.appTheme) private var theme
    let controller: DetailController; let ticket: Ticket; let model: TicketDetailModel; let layout: DetailLayout

    public init(controller: DetailController, ticket: Ticket, model: TicketDetailModel, layout: DetailLayout) {
        self.controller = controller; self.ticket = ticket; self.model = model; self.layout = layout
    }

    private var images: BodyImageHooks {
        let account = controller.account(of: ticket)
        var path: String?
        if case .gitlabItem(let g)? = ticket.providerEntity { path = g.projectPath }
        let t = ticket, ctl = controller, type = ticket.providerType, base = account?.baseUrl
        return BodyImageHooks(loader: { url in await ctl.fetchImage(t, url) },
                              fallbackUrl: { providerImageWebUrl(providerType: type, baseUrl: base, projectPath: path, rawUrl: $0) },
                              onOpenImage: { url in _ = await MainActor.run { openExternally(url) } })
    }

    private var meta: [(String, String)] {
        let ws = controller.workspace(of: ticket)
        var rows: [(String, String)] = [
            (appString("project", "Project"), controller.projects[ticket.projectId]?.name ?? ""),
            (appString("account", "Account"), controller.account(of: ticket)?.handle ?? ""),
            (appString("workspace", "Workspace"), ws?.isPersonal == true ? appString("personal", "Personal") : (ws?.name ?? "")),
            (appString("status", "Status"), statusLabel(ticket.status)),
        ]
        if hasExplicitPriority(ticket) {
            rows.append((appString("priority", "Priority"), priorityLabel(ticket.providerType, ticket.priority).replacingOccurrences(of: "◆ ", with: "")))
        }
        rows.append((appString("updated", "Updated"), formatWhen(ticket.updatedAt, format: controller.settings.dateFormat)))
        return rows
    }

    public var body: some View {
        let tool = controller.registry.module(for: ticket.providerType)
        let isBug: Bool = { if case .zentaoBug? = ticket.providerEntity { true } else { false } }()
        let labels = visibleUserLabels(ticket.labels)
        let colors = labelColorsOf(ticket)
        let prose: CGFloat = 15
        DetailScrollBody(layout: layout) {
            VStack(alignment: .leading, spacing: theme.spacing.s20) {
                if let effort = tool?.buildDetailEffort(ticket: ticket) { effort }
                VStack(alignment: .leading, spacing: 0) {
                    DetailSectionTitle(isBug ? appString("fieldSteps", "Repro steps") : appString("description", "Description"))
                    RichBodyText(ticket.body, html: isHtmlBody(ticket.providerType, ticket.body), fontSize: prose, height: 1.6, images: images)
                        .textSelection(.enabled)
                }
                if let subtasks = tool?.buildDetailSubtasks(ticket: ticket) { subtasks }
                if !labels.isEmpty {
                    VStack(alignment: .leading, spacing: theme.spacing.s8) {
                        SectionLabel(appString("labels", "Labels"))
                        LabelChips(labels, colors: colors.background, textColors: colors.text)
                    }
                }
                if let attachments = tool?.buildDetailAttachments(ticket: ticket) { attachments }
            }
        } sidebar: {
            if let custom = tool?.buildDetailSidebar(ticket: ticket) { custom } else {
                DetailFieldsCard(title: appString("details", "Details"), rows: meta,
                                 valueViews: [appString("status", "Status"): AnyView(TicketStatusPill(ticket: ticket, registry: controller.registry))])
            }
        } activity: {
            VStack(alignment: .leading, spacing: 0) {
                DetailSectionTitle("\(appString("comments", "Comments")) & \(appString("activity", "Activity"))")
                CommentsSection(controller: controller, ticket: ticket, model: model, images: images)
            }
        }
    }
}
