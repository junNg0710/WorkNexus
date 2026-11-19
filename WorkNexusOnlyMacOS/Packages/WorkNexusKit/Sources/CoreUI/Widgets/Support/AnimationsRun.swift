/// Ported from: Flutter's `TickerMode` around each kept-alive section (lib/app/shell/viewport.dart).
import SwiftUI

private struct AnimationsRunKey: EnvironmentKey { static let defaultValue = true }

public extension EnvironmentValues {
    /// False inside a view kept mounted but out of sight (a section behind the one on screen): its endless animations —
    /// a placeholder's sheen, the typing dots — stand still instead of redrawing many times a second for nobody.
    var animationsRun: Bool {
        get { self[AnimationsRunKey.self] }
        set { self[AnimationsRunKey.self] = newValue }
    }
}
