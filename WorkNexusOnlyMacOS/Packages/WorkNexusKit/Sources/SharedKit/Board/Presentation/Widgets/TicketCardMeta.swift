import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/ticket_card_meta.dart (`AssigneeChip`)
/// Assignee avatar + name, or "Unassigned". With an `accountId` the host's `\.personAvatar` builder supplies the
/// authenticated avatar (ZenTao); otherwise a tinted initial.
public struct AssigneeChip: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.personAvatar) private var avatar
    let assignee: String?; let accent: Color; let accountId: String?
    private static let size: CGFloat = 18

    public init(_ assignee: String?, accent: Color, accountId: String? = nil) {
        self.assignee = assignee; self.accent = accent; self.accountId = accountId
    }

    public var body: some View {
        let c = theme.colors
        let name = assignee?.trimmingCharacters(in: .whitespaces) ?? ""
        if name.isEmpty {
            HStack(spacing: theme.spacing.s4) {
                Image(systemName: "person.fill.xmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3)
                Text(appString("unassigned", "Unassigned")).font(theme.typography.mono).foregroundStyle(c.tx3)
            }
        } else {
            HStack(spacing: theme.spacing.s6) {
                if let accountId, let avatar {
                    avatar(PersonAvatarRequest(accountId: accountId, name: name, diameter: Self.size))
                } else {
                    Text(String(name.prefix(1)).uppercased()).font(theme.typography.badge).foregroundStyle(accent)
                        .frame(width: Self.size, height: Self.size).background(accent.opacity(0.22), in: Circle())
                }
                Text(name).font(theme.typography.meta).foregroundStyle(c.tx2).lineLimit(1)
            }
        }
    }
}
