import CoreDomain
import CoreUI
import FeaturePets
import SharedKit
import SwiftUI

/// The pet settings: whether a pet shows, where (in the window or floating on the desktop) and how big; how it moves, what
/// it reacts to and how it speaks (`PetBehaviorCards`); what a click on it does; which pet - the TBChat character or one
/// installed from codex-pets.net. A way back to how everything came heads the page. Not in the Flutter app.
struct PetSettingsPage: View {
    let root: CompositionRoot

    var body: some View {
        let shell = root.shell, s = shell.settings
        SettingsPage(title: appString("petSettings", "Pet")) {
            // First on the page: the gallery at the bottom keeps growing ("Load more"), which would push it out of reach.
            PetResetCard(shell: shell)
            SettingsCard(title: appString("petSettings", "Pet"),
                         subtitle: appString("petSettingsHint", "A small companion that reacts to chats, syncs and tickets waiting for you.")) {
                SettingsToggleRow(label: appString("showPet", "Show the pet"), isOn: s.showPet) { on in
                    shell.updateSettings { $0.showPet = on }
                }
                SettingsRow(label: appString("petDisplay", "Where it stands")) {
                    SettingsSegmented(values: [(.inWindow, appString("petInWindow", "In the window")),
                                               (.floating, appString("petFloating", "On the desktop"))] as [(PetDisplay, String)],
                                      value: s.petDisplay) { v in shell.updateSettings { $0.petDisplay = v; $0.showPet = true } }
                }
                SettingsRow(label: appString("petSize", "Size")) {
                    SettingsSlider(value: s.petScale, range: AppSettings.petScaleRange, step: 0.1,
                                   format: { "\(Int(($0 * 100).rounded()))%" }) { v in shell.updateSettings { $0.petScale = v } }
                }
            }
            PetMotionCard(shell: shell)
            PetReactionsCard(shell: shell)
            if s.petDisplay == .floating { PetClickCard(shell: shell) }
            SettingsCard(title: appString("petChoose", "Choose a pet")) {
                PetGalleryView(library: root.petLibrary, gallery: root.petGallery, selectedId: s.petId) { id in
                    shell.updateSettings { $0.petId = id; $0.showPet = true }
                }
            }
        }
    }
}

/// What a click on the pet on the desktop does, and whether it stays there when WorkNexus is hidden.
private struct PetClickCard: View {
    let shell: ShellModel

    var body: some View {
        let s = shell.settings
        SettingsCard(title: appString("petCardClick", "Clicks")) {
            SettingsRow(label: appString("petClickInFront", "A click on the pet while WorkNexus is in front")) {
                SettingsSegmented(values: [(false, appString("petClickHidesApp", "Hides WorkNexus")),
                                           (true, appString("petClickGoesBack", "Goes back to the previous app"))],
                                  value: s.petClickGoesBack) { v in shell.updateSettings { $0.petClickGoesBack = v } }
            }
            SettingsToggleRow(label: appString("petStaysWhenAppHides", "Stays on the desktop when WorkNexus is hidden"),
                              isOn: s.petStaysWhenAppHides) { on in
                shell.updateSettings { $0.petStaysWhenAppHides = on }
            }
        }
    }
}

/// Puts every setting of the pet back as it came (after asking); the pet chosen stays.
private struct PetResetCard: View {
    let shell: ShellModel
    @State private var asking = false

    var body: some View {
        SettingsCard(title: appString("petResetDefaults", "Reset to defaults")) {
            SettingsRow(label: appString("petResetHint", "Every pet setting goes back to how it came. The pet you chose stays.")) {
                AppButton(appString("reset", "Reset"), systemImage: "arrow.counterclockwise") { asking = true }
            }
        }
        .appConfirmDialog(isPresented: $asking, title: appString("petResetDefaults", "Reset to defaults"),
                          message: appString("petResetHint", "Every pet setting goes back to how it came. The pet you chose stays."),
                          confirmLabel: appString("reset", "Reset")) {
            shell.updateSettings { $0.resetPet() }
        }
    }
}
