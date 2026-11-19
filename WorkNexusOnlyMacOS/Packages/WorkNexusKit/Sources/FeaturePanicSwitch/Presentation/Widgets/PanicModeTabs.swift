import CoreUI
import SwiftUI

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_switch_settings_card.dart (`_ModeTabs`)
/// The card's tabs and the open one's settings: "Official" (the team group), "Demo" (a chat of your own) and "Pet" (the
/// gesture that sets it off; the Flutter app's "Floating button" tab).
struct PanicModeTabs: View {
    enum Tab: CaseIterable { case official, demo, pet }

    @Environment(\.appTheme) private var theme
    @State private var tab = Tab.official
    let model: PanicSwitchModel
    let config: PanicSwitchConfig
    /// The team group's title, or a stand-in until it is found.
    let team: String
    let save: PanicSave

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline)
            AppSegmentedTabs(Tab.allCases.map { t in AppSegmentedTab(label: label(t), active: tab == t) { tab = t } })
                .fixedSize()
                .padding(theme.spacing.s20)
            switch tab {
            case .official: PanicOfficialTab(model: model, config: config, team: team, save: save)
            case .demo: PanicDemoTab(chats: model.chats, config: config, save: save)
            case .pet: PanicPetTab(config: config, save: save)
            }
        }
    }

    private func label(_ t: Tab) -> String {
        switch t {
        case .official: appString("panicSwitchTabRelease", "Official")
        case .demo: config.demoMode ? appString("panicSwitchTabDemoOn", "Demo · on") : appString("panicSwitchTabDemo", "Demo")
        case .pet: appString("petSettings", "Pet")
        }
    }
}

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_release_tab.dart
/// The "Official" tab: the team group trigger — how it works, the apps to open, who may set it off, and the debounce.
struct PanicOfficialTab: View {
    let model: PanicSwitchModel
    let config: PanicSwitchConfig
    let team: String
    let save: PanicSave

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanicSteps(steps: [
                .init(icon: "cursorarrow.click.2", text: PanicPetTab.howStep(config)),
                .init(icon: "paperplane", text: appFormat("panicSwitchHowStep2", "The \"Thầy vô\" sticker goes to %1$@.", team)),
                .init(icon: "macwindow.on.rectangle",
                      text: appString("panicSwitchHowStep3", "Every computer in the group, yours included, opens the chosen apps and hides all the others.")),
            ])
            AppExpandableCardSection(title: appString("panicSwitchTargetLabel", "Apps to open"),
                                     hint: appString("panicSwitchTargetHint", "Tick as many as you like. Every other open app is hidden."),
                                     content: { PanicAppChecklist(apps: model.apps, config: config, save: save) })
            AppExpandableCardSection(title: appString("panicSwitchSendersLabel", "Who can set it off"),
                                     hint: appString("panicSwitchSendersHint", "Anyone in the group by default. Untick it to allow only a few people."),
                                     content: { PanicSenderList(members: model.members, config: config, save: save) })
            PanicDebounceSection(config: config, save: save)
        }
    }
}

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_demo_tab.dart
/// The "Demo" tab: a second trigger, from the pet's right-click menu and to a chat of your own, to try the switch without
/// bothering the team. It shares the apps and the pet with the official tab.
struct PanicDemoTab: View {
    @Environment(\.appTheme) private var theme
    let chats: [PanicChat]
    let config: PanicSwitchConfig
    let save: PanicSave

    var body: some View {
        let chat = chats.first { $0.chat.gid == config.demoChatGid }?.title
        VStack(alignment: .leading, spacing: 0) {
            PanicSteps(steps: [
                .init(icon: "cursorarrow.click", text: appString("panicSwitchPetDemoStep1", "Right-click the pet and pick \"Demo\".")),
                .init(icon: "paperplane", text: appFormat("panicSwitchDemoStep2", "A demo sticker goes to %1$@.",
                                                          chat ?? appString("panicSwitchDemoChatFallback", "your demo chat"))),
                .init(icon: "flask", text: appString("panicSwitchDemoStep3", "Only computers in demo mode on that chat, yours included, switch apps. The team is not bothered.")),
            ])
            AppExpandableCardSection(title: appString("panicSwitchDemoModeLabel", "Turn on demo mode"),
                                     hint: appString("panicSwitchPetDemoModeHint", "Uses the same pet and apps: right-click the pet and pick \"Demo\"."),
                                     trailing: { PanicToggle(isOn: config.demoMode) { on in save { $0.demoMode = on } } })
            if config.demoMode {
                AppExpandableCardSection(title: appString("panicSwitchDemoChatLabel", "Demo chat"),
                                         hint: appString("panicSwitchDemoChatHint", "Only computers in demo mode on this same chat switch apps."),
                                         content: {
                    PanicChatPicker(chats: chats, value: config.demoChatGid) { picked in save { $0.demoChatGid = picked.chat.gid } }
                })
            }
            AppInlineNote(appString("panicSwitchPetDemoShared", "The apps to open are set in the Official tab, the gesture in the Pet tab."))
                .padding(theme.spacing.s20)
        }
    }
}
