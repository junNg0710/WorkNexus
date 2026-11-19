import CoreUI
import SwiftUI

/// Adapted from: lib/features/panic_switch/presentation/widgets/panic_button_tab.dart
/// The "Pet" tab (the Flutter app's "Floating button" tab): whether the pet sets the switch off and, while it does, with which
/// gesture — two or three quick clicks, or pressed and held for a number of seconds. The floating button's size and fade
/// do not apply to the pet.
struct PanicPetTab: View {
    @Environment(\.appTheme) private var theme
    let config: PanicSwitchConfig
    let save: PanicSave

    /// A gesture's name, as the segmented tabs show it.
    static func label(_ gesture: PanicPetGesture) -> String {
        switch gesture {
        case .doubleClick: appString("panicSwitchGestureDouble", "Double-click")
        case .tripleClick: appString("panicSwitchGestureTriple", "Triple-click")
        case .hold: appString("panicSwitchGestureHold", "Press and hold")
        }
    }

    /// The first step of "How it works" (Official), with the gesture chosen.
    static func howStep(_ config: PanicSwitchConfig) -> String {
        switch config.petGesture {
        case .hold: appFormat("panicSwitchPetHowHold", "Press and hold the pet for %1$@ seconds.", "\(config.petHoldSeconds)")
        case .doubleClick, .tripleClick: appFormat("panicSwitchPetHowStep1", "%1$@ the pet.", label(config.petGesture))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppExpandableCardSection(title: appString("panicSwitchPetLabel", "Alert from the pet"),
                                     hint: appString("panicSwitchPetTabHint", "The pet sets it off, in the window or on the desktop. The pet must be shown (Settings › Pet)."),
                                     trailing: { PanicToggle(isOn: config.overlayVisible) { on in save { $0.overlayVisible = on } } })
            if config.overlayVisible {
                AppExpandableCardSection(title: appString("panicSwitchGestureLabel", "Set it off by"),
                                         hint: appString("panicSwitchPetGestureTabHint", "For Official. Demo: right-click the pet and pick \"Demo\"."),
                                         content: {
                    HStack(spacing: theme.spacing.s12) {
                        AppSegmentedTabs(PanicPetGesture.allCases.map { g in
                            AppSegmentedTab(label: Self.label(g), active: config.petGesture == g) { save { $0.petGesture = g } }
                        })
                        .fixedSize()
                        if config.petGesture == .hold {
                            PanicHoldStepper(seconds: config.petHoldSeconds) { s in save { $0.petHoldSeconds = s } }
                        }
                    }
                })
            }
        }
    }
}

/// How long the pet is held for it: 1 to 30 seconds.
private struct PanicHoldStepper: View {
    @Environment(\.appTheme) private var theme
    let seconds: Int
    let onChange: (Int) -> Void

    var body: some View {
        Stepper(value: Binding(get: { seconds }, set: onChange), in: PanicSwitchConstants.petHoldRange) {
            Text(appFormat("panicSwitchPetHoldSeconds", "%1$@ seconds", "\(seconds)"))
                .font(theme.typography.meta).foregroundStyle(theme.colors.tx2).monospacedDigit()
        }
        .fixedSize()
    }
}
