import CoreUI
import SwiftUI

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_sender_list.dart
/// The team group's members, each with their avatar, ticked when their sticker may set the switch off on this computer;
/// with "anyone", all are shown ticked. (The demo chat accepts anyone.)
struct PanicSenderList: View {
    /// Room for about eight people before the list scrolls.
    static let maxHeight: CGFloat = 280

    let members: PanicSwitchModel.Members
    let config: PanicSwitchConfig
    let save: PanicSave

    var body: some View {
        if config.chatGid == nil {
            PanicNote(text: appString("panicSwitchSendersNeedGroup", "The team group has not been found yet."))
        } else {
            switch members {
            case .idle, .loading: ProgressView().progressViewStyle(.linear).frame(maxWidth: .infinity)
            case .failed: PanicNote(text: appString("panicSwitchSendersFailed", "Could not load the chat's members."))
            case .loaded(let people): PanicSenderChecks(people: people, config: config, save: save)
            }
        }
    }
}

/// "Anyone in the chat", then every member — shown with "anyone" too, ticked and greyed, so it is clear who that is.
private struct PanicSenderChecks: View {
    @Environment(\.appTheme) private var theme
    let people: [PanicPerson]
    let config: PanicSwitchConfig
    let save: PanicSave

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PanicCheckRow(label: appString("panicSwitchAnySender", "Anyone in the chat"), picked: config.anySender) {
                    save { $0.anySender.toggle() }
                }
                ForEach(people) { person in
                    PanicCheckRow(label: person.displayName, detail: person.account,
                                  picked: config.anySender || config.allowedSenderIds.contains(person.userId),
                                  enabled: !config.anySender, onToggle: { toggle(person.userId) }) {
                        UserAvatar(name: person.displayName, url: person.avatarUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                                   size: theme.sizes.icon20)
                    }
                }
            }
        }
        .frame(maxHeight: PanicSenderList.maxHeight).fixedSize(horizontal: false, vertical: true)
    }

    private func toggle(_ id: Int) {
        save { c in
            if c.allowedSenderIds.contains(id) { c.allowedSenderIds.removeAll { $0 == id } } else { c.allowedSenderIds.append(id) }
        }
    }
}
