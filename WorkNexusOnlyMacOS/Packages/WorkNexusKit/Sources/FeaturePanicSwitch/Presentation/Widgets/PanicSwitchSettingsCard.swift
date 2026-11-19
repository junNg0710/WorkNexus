import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_switch_settings_card.dart (+ panic_switch_save.dart)
/// Settings' "Thầy vô" card: one "Turn on Thầy vô" switch at the top (off: nothing is sent, stickers are ignored, the tabs
/// are hidden), then three tabs so none reads as one long list — "Official" (the team group), "Demo" (a chat of your own)
/// and "Pet" (the gesture). Shown only to users of the ZenTao the feature is offered for; on its own settings page it is
/// shown flat (`appExpandableCardFlat`).
public struct PanicSwitchSettingsCard: View {
    @Environment(\.appTheme) private var theme
    let model: PanicSwitchModel
    let initiallyExpanded: Bool

    public init(model: PanicSwitchModel, initiallyExpanded: Bool = false) {
        self.model = model; self.initiallyExpanded = initiallyExpanded
    }

    public var body: some View {
        if model.account != nil {
            if model.loadFailed {
                AppExpandableCard(icon: PanicCardSections.icon, title: PanicCardSections.title,
                                  summary: appString("panicSwitchLoadFailed", "Could not load these settings")) {
                    // Shown flat (no header) on the card's own page, the failure still needs saying.
                    PanicNote(text: appString("panicSwitchLoadFailed", "Could not load these settings")).padding(theme.spacing.s20)
                }
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
        AppExpandableCard(icon: Self.icon, title: Self.title, summary: summary, initiallyExpanded: initiallyExpanded) {
            AppExpandableCardSection(title: appString("panicSwitchEnabledLabel", "Turn on Thầy vô"),
                                     hint: appString("panicSwitchPetEnabledHint", "Off: on this computer the pet does not set it off, nothing is sent and arriving stickers are ignored."),
                                     trailing: { PanicToggle(isOn: config.enabled) { on in save { $0.enabled = on } } })
            if config.enabled {
                PanicModeTabs(model: model, config: config,
                              team: title(of: config.chatGid) ?? appString("panicSwitchTeamFallback", "the team group"), save: save)
            }
        }
        .task(id: model.account?.id) { await model.watchChats(selfTitle: appString("panicSwitchSelfChat", "Send to myself (try it out)")) }
        .task { await model.loadApps() }
        .task(id: config.chatGid) { await model.loadMembers() }
    }

    private var summary: String {
        guard config.enabled else { return appString("panicSwitchSummaryOff", "Off on this computer") }
        let team: String
        if let group = title(of: config.chatGid) {
            team = config.anySender
                ? appFormat("panicSwitchSummaryAnyone", "%1$@ · anyone can set it off", group)
                : appFormat("panicSwitchSummary", "%1$@ · %2$@ people can set it off", group, "\(config.allowedSenderIds.count)")
        } else {
            team = appString("panicSwitchNoGroup", "Team group not found")
        }
        return config.demoMode ? appFormat("panicSwitchSummaryWithDemo", "%1$@ · demo mode on", team) : team
    }

    private func title(of gid: String?) -> String? { model.chats.first { $0.chat.gid == gid }?.title }

    /// Saves a change, saying so when it could not be kept.
    private func save(_ change: @escaping (inout PanicSwitchConfig) -> Void) {
        Task {
            if case .failure = await model.edit(change) {
                toasts?.show(appString("panicSwitchSaveFailed", "Could not save the setting"), kind: .error)
            }
        }
    }
}
