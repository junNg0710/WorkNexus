import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_switch_settings_card.dart (+ panic_chat_picker.dart,
/// panic_try_button.dart, panic_switch_save.dart)
/// Settings' "Thầy vô" card: the floating button that sends the sticker, and what this computer does when the sticker
/// arrives. Shown only to users of the ZenTao the feature is offered for.
public struct PanicSwitchSettingsCard: View {
    let model: PanicSwitchModel
    let initiallyExpanded: Bool

    public init(model: PanicSwitchModel, initiallyExpanded: Bool = false) {
        self.model = model; self.initiallyExpanded = initiallyExpanded
    }

    public var body: some View {
        if model.account != nil {
            if model.loadFailed {
                AppExpandableCard(icon: PanicCardSections.icon, title: PanicCardSections.title,
                                  summary: appString("panicSwitchLoadFailed", "Could not load these settings")) { EmptyView() }
            } else if let config = model.config {
                PanicCardSections(model: model, config: config, initiallyExpanded: initiallyExpanded)
            }
        }
    }
}

/// The card itself, over the loaded settings.
private struct PanicCardSections: View {
    static let icon = "light.beacon.max"
    static var title: String { appString("panicSwitchTitle", "Thầy vô (boss alert)") }

    @Environment(\.toasts) private var toasts
    let model: PanicSwitchModel
    let config: PanicSwitchConfig
    let initiallyExpanded: Bool

    var body: some View {
        let team = title(of: config.chatGid)
        AppExpandableCard(icon: Self.icon, title: Self.title, summary: summary, initiallyExpanded: initiallyExpanded) {
            AppExpandableCardSection(title: appString("panicSwitchOverlayLabel", "Floating button"),
                                     hint: appString("panicSwitchOverlayHint", "A button above every app: click it three times to send the sticker. Drag it to move it."),
                                     trailing: { PanicToggle(isOn: config.overlayVisible) { on in save { $0.overlayVisible = on } } })
            AppExpandableCardSection(title: appString("panicSwitchGroupLabel", "Team group"),
                                     hint: appString("panicSwitchTeamGroupHint", "Where the sticker is sent and listened for, outside test mode."),
                                     trailing: { PanicValueText(text: team ?? appString("panicSwitchNoGroup", "Team group not found")) })
            AppExpandableCardSection(title: appString("panicSwitchTestModeLabel", "Test mode"),
                                     hint: appString("panicSwitchTestModeHint", "Use a chat of your choice instead of the team group, for both sending and listening, to try it without bothering anyone."),
                                     trailing: { PanicToggle(isOn: config.testMode) { on in save { $0.testMode = on } } })
            if config.testMode {
                AppExpandableCardSection(title: appString("panicSwitchTestChatLabel", "Test chat"),
                                         hint: appString("panicSwitchTestChatHint", "The sticker is sent here and listened for here. \"Send to myself\" switches apps on this computer as soon as you click."),
                                         content: { PanicChatPicker(chats: model.chats, value: config.testChatGid, onChanged: pickTestChat) })
            }
            AppExpandableCardSection(title: appString("panicSwitchReceiveLabel", "React to the sticker"),
                                     hint: appString("panicSwitchReceiveHint", "When the \"Thầy vô\" sticker arrives from someone allowed below, switch apps on this computer."),
                                     trailing: { PanicToggle(isOn: config.enabled) { on in save { $0.enabled = on } } })
            AppExpandableCardSection(title: appString("panicSwitchSendersLabel", "Who can set it off"),
                                     hint: appString("panicSwitchSendersHint", "Whose sticker switches apps here: anyone in the chat, or only the people ticked."),
                                     content: { PanicSenderList(members: model.members, config: config, save: save) })
            Group {
                AppExpandableCardSection(title: appString("panicSwitchTargetLabel", "App to open"),
                                         hint: appString("panicSwitchTargetHint", "Brought to the front, or started when it is not running."),
                                         content: { PanicTargetAppPicker(apps: model.apps, config: config, save: save) })
                AppExpandableCardSection(title: appString("panicSwitchHideLabel", "Apps to hide"),
                                         hint: appString("panicSwitchHideHint", "Hidden at the same moment (minimised on Windows and Linux)."),
                                         content: { PanicHiddenAppsPicker(apps: model.apps, config: config, save: save) })
                AppExpandableCardSection(title: appString("panicSwitchTryLabel", "Try it now"),
                                         hint: appString("panicSwitchTryHint", "Switches apps on this computer right away, with no chat involved (works while the chat server is down). WorkNexus hides too when that is on."),
                                         trailing: { AppButton(appString("panicSwitchTryButton", "Try"), systemImage: "play") { tryNow() } })
                AppExpandableCardSection(title: appString("panicSwitchHideSelfLabel", "Hide WorkNexus too"),
                                         hint: appString("panicSwitchHideSelfHint", "Hidden on macOS, minimised on Windows and Linux."),
                                         trailing: { PanicToggle(isOn: config.hideSelf) { on in save { $0.hideSelf = on } } })
                AppExpandableCardSection(title: appString("panicSwitchDebounceLabel", "At most once every"),
                                         hint: appString("panicSwitchDebounceHint", "For both sending and switching, so repeated stickers do nothing."),
                                         trailing: { PanicDebounceTabs(seconds: config.debounceSeconds) { s in save { $0.debounceSeconds = s } } })
            }
        }
        .task(id: model.account?.id) { await model.watchChats(selfTitle: appString("panicSwitchSelfChat", "Send to myself (try it out)")) }
        .task { await model.loadApps() }
        .task(id: "\(config.receiveChatGid ?? "")|\(config.sendsToSelf)") { await model.loadMembers() }
    }

    private var summary: String {
        if config.testMode { return appString("panicSwitchSummaryTestMode", "Test mode is on") }
        guard let listening = title(of: config.receiveChatGid) else { return appString("panicSwitchNoGroup", "Team group not found") }
        if config.anySender { return appFormat("panicSwitchSummaryAnyone", "%1$@ · anyone can set it off", listening) }
        return appFormat("panicSwitchSummary", "%1$@ · %2$@ people can set it off", listening, "\(config.allowedSenderIds.count)")
    }

    private func title(of gid: String?) -> String? { model.chats.first { $0.chat.gid == gid }?.title }

    /// Senders allowed in one chat mean nothing in another.
    private func pickTestChat(_ picked: PanicChat) {
        save { c in
            guard c.testChatGid != picked.chat.gid else { return }
            c.testChatGid = picked.chat.gid; c.testChatIsSelf = picked.chat.isMyCloud; c.allowedSenderIds = []
        }
    }

    /// Saves a change, saying so when it could not be kept.
    private func save(_ change: @escaping (inout PanicSwitchConfig) -> Void) {
        Task {
            if case .failure = await model.edit(change) {
                toasts?.show(appString("panicSwitchSaveFailed", "Could not save the setting"), kind: .error)
            }
        }
    }

    /// Runs the switch here right away, with no chat involved — to check the chosen apps, also while the chat server is down.
    private func tryNow() {
        Task {
            if case .failure(let f) = await model.tryNow() {
                toasts?.show("\(appString("panicSwitchTryFailed", "Some steps did not work")): \(f.message)", kind: .error)
            }
        }
    }
}

/// Picks one of `chats` (test mode's chat), by title, with a search box.
private struct PanicChatPicker: View {
    let chats: [PanicChat]
    let value: String?
    let onChanged: (PanicChat) -> Void

    var body: some View {
        SearchableDropdownField(items: chats, value: chats.first { $0.chat.gid == value }, labelOf: \.title,
                                hintText: appString("panicSwitchGroupPick", "Pick a chat"),
                                searchHint: appString("panicSwitchSearch", "Search…"),
                                emptyLabel: appString("panicSwitchNoMatches", "No matches"), onChanged: onChanged)
    }
}

/// The debounce choices (with the saved one among them when the card does not offer it).
private struct PanicDebounceTabs: View {
    let seconds: Int
    let onPick: (Int) -> Void

    var body: some View {
        let choices = Set(PanicSwitchConstants.debounceChoices + [seconds]).sorted()
        AppSegmentedTabs(choices.map { s in
            AppSegmentedTab(label: appFormat("panicSwitchSeconds", "%1$@s", "\(s)"), active: seconds == s) { onPick(s) }
        })
    }
}

/// An on/off switch beside a section's title.
private struct PanicToggle: View {
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: onChange)).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
}

/// A read-only value beside a section's title.
private struct PanicValueText: View {
    @Environment(\.appTheme) private var theme
    let text: String

    var body: some View {
        Text(text).font(theme.typography.body).foregroundStyle(theme.colors.tx2).lineLimit(1)
    }
}
