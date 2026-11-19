import CoreUI
import SwiftUI

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_sender_list.dart
/// "Anyone in the chat", then — when that is off — the chat's members, each ticked when their sticker may set the switch
/// off on this computer.
struct PanicSenderList: View {
    /// Room for about eight people before the list scrolls.
    static let maxHeight: CGFloat = 280

    let members: PanicSwitchModel.Members
    let config: PanicSwitchConfig
    let save: (@escaping (inout PanicSwitchConfig) -> Void) -> Void

    var body: some View {
        if config.receiveChatGid == nil {
            PanicNote(text: appString("panicSwitchSendersNeedGroup", "Pick the test chat first."))
        } else if config.sendsToSelf {
            PanicNote(text: appString("panicSwitchSelfChatNote", "Sent to yourself: clicking the button switches apps on this computer right away."))
        } else {
            switch members {
            case .idle, .loading: ProgressView().progressViewStyle(.linear).frame(maxWidth: .infinity)
            case .failed: PanicNote(text: appString("panicSwitchSendersFailed", "Could not load the chat's members."))
            case .loaded(let people): PanicSenderChecks(people: people, config: config, save: save)
            }
        }
    }
}

/// The check boxes: anyone, else each member.
private struct PanicSenderChecks: View {
    let people: [PanicPerson]
    let config: PanicSwitchConfig
    let save: (@escaping (inout PanicSwitchConfig) -> Void) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PanicCheckRow(label: appString("panicSwitchAnySender", "Anyone in the chat"), detail: nil, picked: config.anySender) {
                    save { $0.anySender.toggle() }
                }
                if !config.anySender {
                    ForEach(people) { person in
                        PanicCheckRow(label: person.displayName, detail: person.account,
                                      picked: config.allowedSenderIds.contains(person.userId)) {
                            save { c in
                                if c.allowedSenderIds.contains(person.userId) { c.allowedSenderIds.removeAll { $0 == person.userId } }
                                else { c.allowedSenderIds.append(person.userId) }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: PanicSenderList.maxHeight).fixedSize(horizontal: false, vertical: true)
    }
}

/// One tickable line: a check box, the name and, faded, the account.
private struct PanicCheckRow: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let label: String
    let detail: String?
    let picked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: theme.spacing.s10) {
                Image(systemName: picked ? "checkmark.square.fill" : "square").font(.system(size: theme.sizes.icon16))
                    .foregroundStyle(picked ? theme.colors.accent : theme.colors.tx3)
                Text(label).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
                Spacer(minLength: theme.spacing.s8)
                if let detail { Text(detail).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1) }
            }
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s4)
            .background(hovering ? theme.colors.sel : .clear, in: RoundedRectangle(cornerRadius: theme.radii.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

/// A line of explanation in place of a list.
struct PanicNote: View {
    @Environment(\.appTheme) private var theme
    let text: String

    var body: some View {
        Text(text).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2).fixedSize(horizontal: false, vertical: true)
    }
}
