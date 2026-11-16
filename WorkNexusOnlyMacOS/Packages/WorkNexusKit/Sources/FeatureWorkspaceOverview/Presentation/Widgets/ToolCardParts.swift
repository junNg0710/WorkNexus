/// Ported from: lib/features/workspace_overview/presentation/widgets/tool_card_parts.dart
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// The pieces of a tool account's Overview card, shared by the compact `ToolCard` and the ZenTao section.

/// The tool's badge, its name and "handle · role".
struct ToolCardIdentity: View {
    @Environment(\.appTheme) private var theme
    let account: Account
    let module: any ToolModule

    var body: some View {
        let role = module.roleLabel
        HStack(spacing: theme.spacing.s8) {
            BrandLogoBadge(account.providerType, size: theme.sizes.control32)
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text(account.providerType.displayName).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                Text(role.isEmpty ? account.handle : "\(account.handle) · \(role)")
                    .font(theme.typography.caption).foregroundStyle(theme.colors.tx2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// "Open {Tool} →": the account in its tool.
struct ToolOpenButton: View {
    let model: OverviewModel
    let account: Account

    var body: some View {
        AppButton(OL.openToolAction(account.providerType.displayName), kind: .secondary) { model.select(account) }
            .frame(maxWidth: .infinity)
    }
}

/// One chip per tool section, each opening the account in that section.
struct ToolSectionChips: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account
    let module: any ToolModule

    var body: some View {
        FlowLayout(spacing: theme.spacing.s4) {
            ForEach(module.sections.filter(\.available)) { sec in
                HoverSurface(onTap: { model.select(account, section: sec.id) }, fill: theme.colors.panel2, cornerRadius: theme.radii.sm) {
                    Text(appString(sec.label, sec.label.capitalized)).font(theme.typography.caption.weight(.medium)).foregroundStyle(theme.colors.tx2)
                        .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s4)
                }
            }
        }
    }
}

/// Wraps its children onto as many rows as the width needs (Flutter `Wrap`).
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, f) in arrange(bounds.width, subviews).frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + (lineSpacing ?? spacing); rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: y + rowH))
    }
}
