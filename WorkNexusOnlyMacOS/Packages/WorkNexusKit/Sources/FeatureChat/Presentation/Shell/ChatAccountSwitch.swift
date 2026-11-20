/// Not in the Flutter app.
import CoreUI
import SwiftUI

/// The chat accounts the user can switch between, handed in by the host (which owns which one is on screen). The chat
/// list shows them at its top: the app used to give them a 300-point column of their own beside the list, a third of the
/// window for two rows.
public struct ChatAccountChoices {
    public struct Choice: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        /// Unread messages in that account's chats.
        public let unread: Int
        public init(id: String, name: String, unread: Int) { self.id = id; self.name = name; self.unread = unread }
    }

    public var choices: [Choice]
    public var currentId: String?
    public var pick: @MainActor (String) -> Void

    public init(choices: [Choice], currentId: String?, pick: @escaping @MainActor (String) -> Void) {
        self.choices = choices; self.currentId = currentId; self.pick = pick
    }

    var current: Choice? { choices.first { $0.id == currentId } ?? choices.first }
    /// Unread messages waiting in the accounts that are not on screen.
    var unreadElsewhere: Int { choices.filter { $0.id != current?.id }.reduce(0) { $0 + $1.unread } }

    /// An account's line in the menu: its name, with its unread count when it has any.
    static func menuTitle(_ choice: Choice) -> String { choice.unread > 0 ? "\(choice.name)  (\(choice.unread))" : choice.name }
}

private struct ChatAccountChoicesKey: EnvironmentKey { static let defaultValue: ChatAccountChoices? = nil }

extension EnvironmentValues {
    var chatAccountChoices: ChatAccountChoices? {
        get { self[ChatAccountChoicesKey.self] }
        set { self[ChatAccountChoicesKey.self] = newValue }
    }
}

public extension View {
    /// The chat accounts to switch between (nil, or one: nothing to switch).
    func chatAccountChoices(_ choices: ChatAccountChoices?) -> some View { environment(\.chatAccountChoices, choices) }
}

/// At the top of the chat list when there are several accounts: the one on screen, with a menu of them all and a badge
/// for what is unread in the others.
struct ChatAccountSwitchRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatAccountChoices) private var accounts
    let compact: Bool

    var body: some View {
        if let accounts, accounts.choices.count > 1, let current = accounts.current {
            AppMenuButton(help: shellString("chatSwitchAccount", "Switch chat account"), items: { items(accounts) }) {
                HStack(spacing: theme.spacing.s6) {
                    Image(systemName: "person.crop.circle").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx2)
                    Text(current.name).font(theme.typography.label).foregroundStyle(theme.colors.tx).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12 - 2, weight: .semibold)).foregroundStyle(theme.colors.tx3)
                    Spacer(minLength: 0)
                    AppCountBadge(accounts.unreadElsewhere)
                }
                .padding(.horizontal, compact ? theme.spacing.s12 : theme.spacing.s20)
                .frame(height: theme.sizes.control32)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
        }
    }

    private func items(_ accounts: ChatAccountChoices) -> [AppNativeMenu.Item] {
        accounts.choices.map { choice in
            AppNativeMenu.Item(ChatAccountChoices.menuTitle(choice), icon: "bubble.left.and.bubble.right", checked: choice.id == accounts.current?.id) {
                if choice.id != accounts.current?.id { accounts.pick(choice.id) }
            }
        }
    }
}
