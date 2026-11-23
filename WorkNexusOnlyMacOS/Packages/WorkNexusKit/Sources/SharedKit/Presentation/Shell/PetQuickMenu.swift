import CoreDomain
import CoreUI
import SwiftUI

/// The pet's quick controls, in its right-click menu: stand still (and walk about again), keep quiet for an hour (and
/// stop keeping quiet) - without opening the settings. Not in the Flutter app.
struct PetQuickMenu: View {
    let model: ShellModel
    /// How long "Quiet for 1 hour" keeps it quiet.
    static let quietFor: TimeInterval = 3600

    var body: some View {
        let behavior = model.settings.petBehavior, quiet = PetReacts(behavior).isQuiet
        Button(behavior.activity.wanders ? appString("petMenuStandStill", "Stand still") : appString("petMenuWalkAgain", "Walk about again")) {
            model.updateSettings { $0.petBehavior.toggleStandingStill() }
        }
        Button(quiet ? appString("petMenuSpeakAgain", "Stop being quiet") : appString("petMenuQuietHour", "Quiet for 1 hour")) {
            model.updateSettings { $0.petBehavior.quietUntil = quiet ? nil : Date().addingTimeInterval(Self.quietFor) }
        }
    }
}
