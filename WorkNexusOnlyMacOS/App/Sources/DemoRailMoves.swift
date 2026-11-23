import FeatureMiniApps
import Foundation
import SharedKit

/// DEBUG builds only: `WN_DEMO_RAIL_MOVE=<place>:<steps>|<place>><place>,…` reorders the rail's own apps in a demo run, one
/// move every two seconds from the sixth, and prints the rail's places with their shortcuts before and after each - to try
/// the shared order of websites and Mac apps without a hand on the mouse. `<place>` is a button's place id
/// (`miniapp:<id>`, `macapp:<id>`); `:<steps>` is the context menu's Move up (`-1`) / Move down (`1`); `>` is what
/// dropping the first button on the second does.
enum DemoRailMoves {
    @MainActor
    static func start(shell: ShellModel, rail: RailAppsModel) {
        #if DEBUG
        guard let spec = ProcessInfo.processInfo.environment["WN_DEMO_RAIL_MOVE"] else { return }
        func report(_ what: String) {
            let keys = shell.railShortcuts
            let places = shell.railPlaces.map { "\($0.name)[\(keys[$0.id]?.display ?? "-")]" }.joined(separator: " ")
            print("DEMORAIL \(what): \(places)"); fflush(stdout)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            report("start")
            for move in spec.split(separator: ",").map(String.init) {
                if let arrow = move.firstIndex(of: ">"), let target = RailAppRef(placeId: String(move[move.index(after: arrow)...])) {
                    let taken = rail.drop(String(move[..<arrow]), onto: target)
                    if !taken { print("DEMORAIL \(move): not taken") }
                } else if let colon = move.lastIndex(of: ":"), let steps = Int(move[move.index(after: colon)...]),
                          let ref = RailAppRef(placeId: String(move[..<colon])) {
                    await rail.move(ref, by: steps)
                }
                try? await Task.sleep(for: .seconds(2))
                report(move)
            }
        }
        #endif
    }
}
