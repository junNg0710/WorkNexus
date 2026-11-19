import CoreUI
import FeaturePanicSwitch
import SwiftUI

/// Ported from: lib/app/shell/workspace_settings_page.dart (`SettingsCardPage.panicSwitch`)
/// The "Thầy vô" page of the Settings sidebar, listed only for users of the oasoft ZenTao: its card, shown open and without
/// its header — the page title names it.
struct PanicSwitchSettingsPage: View {
    let root: CompositionRoot

    var body: some View {
        SettingsPage(title: appString("panicSwitchTitle", "Thầy vô (boss alert)")) {
            PanicSwitchSettingsCard(model: root.panic.model, initiallyExpanded: true).appExpandableCardFlat()
        }
    }
}
