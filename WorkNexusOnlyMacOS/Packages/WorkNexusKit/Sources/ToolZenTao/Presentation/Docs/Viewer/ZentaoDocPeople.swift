/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_people.dart
import CoreDomain
import CoreUI
import SwiftUI

/// "[avatar] ViPham created" / "[avatars] edited" in a document's header, as ZenTao's web shows it. A tap opens a card
/// of these people, each with a button to message them (when the host provides one).
struct ZentaoDocPeople: View {
    @Environment(\.appTheme) private var theme
    @State private var open = false
    let accountId: String; let people: [ZenTaoDocPerson]
    /// What they did, after the faces ("created", "edited").
    let action: String
    /// The card's heading ("Created by", "Edited by").
    let title: String

    /// More faces than this collapse into the stack's last one.
    static let maxFaces = 3

    var body: some View {
        if !people.isEmpty {
            let c = theme.colors
            let face = theme.sizes.icon20
            let shown = Array(people.prefix(Self.maxFaces))
            let step = face * 2 / 3
            HoverSurface(onTap: { open.toggle() }, cornerRadius: theme.radii.pill) {
                HStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { i, p in
                            // A ring in the page colour parts overlapping faces; the face sits inside it, not under it.
                            ZentaoDocFace(accountId: accountId, person: p, diameter: face - theme.spacing.s2 * 2)
                                .padding(theme.spacing.s2).background(c.card, in: Circle()).offset(x: step * CGFloat(i))
                        }
                    }
                    .frame(width: face + step * CGFloat(shown.count - 1), height: face, alignment: .leading)
                    .padding(.trailing, theme.spacing.s6)
                    if people.count == 1 {
                        Text(people[0].displayName).font(theme.typography.paragraph.weight(.semibold)).foregroundStyle(c.tx).lineLimit(1)
                            .padding(.trailing, theme.spacing.s4)
                    } else if people.count > Self.maxFaces {
                        Text(verbatim: "+\(people.count - Self.maxFaces)").font(theme.typography.paragraph).foregroundStyle(c.tx2)
                            .padding(.trailing, theme.spacing.s4)
                    }
                    Text(action).font(theme.typography.paragraph).foregroundStyle(c.tx2).lineLimit(1)
                }
                .fixedSize()
                .padding(EdgeInsets(top: theme.spacing.s2, leading: theme.spacing.s2, bottom: theme.spacing.s2, trailing: theme.spacing.s10))
            }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ZentaoDocPeopleCard(accountId: accountId, title: title, people: people)
            }
        }
    }
}

private struct ZentaoDocPeopleCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.zentaoDocPersonAction) private var personAction
    let accountId: String; let title: String; let people: [ZenTaoDocPerson]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(theme.typography.label).foregroundStyle(theme.colors.tx3)
                .padding(EdgeInsets(top: 0, leading: theme.spacing.s12, bottom: theme.spacing.s6, trailing: theme.spacing.s12))
            ForEach(people, id: \.account) { person in
                HStack(spacing: theme.spacing.s10) {
                    ZentaoDocFace(accountId: accountId, person: person, diameter: theme.sizes.control32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(person.displayName).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                        if person.name != nil { Text(person.account).font(theme.typography.caption).foregroundStyle(theme.colors.tx3) }
                    }
                    Spacer(minLength: theme.spacing.s10)
                    if let personAction { personAction(ZentaoDocPersonFace(accountId: accountId, name: person.account, diameter: theme.sizes.control32)) }
                }
                .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s6)
            }
        }
        .padding(.vertical, theme.spacing.s8).frame(width: theme.sizes.dialogSm * 0.8)
    }
}

/// A person's chat photo (by login), or their initial without chat.
struct ZentaoDocFace: View {
    @Environment(\.zentaoDocPersonFace) private var face
    let accountId: String; let person: ZenTaoDocPerson; let diameter: CGFloat

    var body: some View {
        if let face { face(ZentaoDocPersonFace(accountId: accountId, name: person.account, diameter: diameter)) }
        else { UserAvatar(name: person.displayName, size: diameter) }
    }
}
