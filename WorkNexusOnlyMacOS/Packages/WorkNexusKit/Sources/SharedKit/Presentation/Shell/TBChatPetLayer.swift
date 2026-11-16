import CoreDomain
import CoreUI
import SwiftUI

/// The TBChat character, standing in the window over the content: it waves when poked, jumps when something is celebrated and
/// shows how syncing is going. Shown while "Show the TBChat character" is on in the settings; where it stands is remembered.
struct TBChatPetLayer: View {
    let model: ShellModel
    @State private var director = PetDirector()
    @State private var sheet = PetSpriteSheet.bundled()
    private static let xKey = "pet.x", yKey = "pet.y"

    /// How the sync of the accounts is going, as the character shows it: trouble first, then work, then no connection.
    static func mood(of statuses: some Collection<AccountSyncStatus>) -> PetDirector.Mood {
        var busy = false, offline = false
        for s in statuses {
            switch s {
            case .error, .authExpired: return .trouble
            case .syncing: busy = true
            case .offline: offline = true
            case .idle: break
            }
        }
        return busy ? .busy : (offline ? .offline : .calm)
    }

    var body: some View {
        Group {
            if model.settings.showPet, let sheet {
                PetView(director: director, sheet: sheet) { x, y in
                    UserDefaults.standard.set(x, forKey: Self.xKey); UserDefaults.standard.set(y, forKey: Self.yKey)
                }
            }
        }
        .padding(8)
        .onAppear {
            let d = UserDefaults.standard
            if d.object(forKey: Self.xKey) != nil { director.place(x: d.double(forKey: Self.xKey), y: d.double(forKey: Self.yKey)) }
        }
        .onChange(of: model.celebration.tick) { _, _ in director.celebrate() }
        .onChange(of: Self.mood(of: model.syncStatuses.values), initial: true) { _, mood in director.mood = mood }
    }
}
