import CoreDomain
import CoreUI
import FeaturePets
import SharedKit
import SwiftUI

/// The pet settings: whether a pet shows and where (in the window or floating on the desktop), whether it looks toward the
/// pointer, and which pet - the TBChat character or one installed from codex-pets.net. Not in the Flutter app.
struct PetSettingsPage: View {
    let root: CompositionRoot

    var body: some View {
        let shell = root.shell, s = shell.settings
        SettingsPage(title: appString("petSettings", "Pet")) {
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
                if s.petDisplay == .floating {
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
                SettingsToggleRow(label: appString("petFollowsCursor", "Looks toward the pointer (pets that can)"), isOn: s.petFollowsCursor) { on in
                    shell.updateSettings { $0.petFollowsCursor = on }
                }
                SettingsToggleRow(label: appString("petShowsDetails", "Says what a new message or notification says"),
                                  isOn: s.petShowsDetails) { on in
                    shell.updateSettings { $0.petShowsDetails = on }
                }
            }
            SettingsCard(title: appString("petChoose", "Choose a pet")) {
                PetGalleryView(library: root.petLibrary, gallery: root.petGallery, selectedId: s.petId) { id in
                    shell.updateSettings { $0.petId = id; $0.showPet = true }
                }
            }
        }
    }
}
