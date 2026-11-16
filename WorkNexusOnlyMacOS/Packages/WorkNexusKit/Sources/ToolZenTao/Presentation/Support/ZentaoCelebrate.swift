/// Ported from: the `celebrationProvider.notifier.celebrate()` calls of zentao_bug_column_card.dart and resolve_dialog.dart
import SwiftUI

private struct ZentaoCelebrateKey: EnvironmentKey { static let defaultValue: @MainActor () -> Void = {} }

public extension EnvironmentValues {
    /// Fires the app's fireworks. ToolZenTao calls it when a bug is resolved as Fixed - by dropping its card on the
    /// Resolved / Verify column or from the Resolve dialog. A no-op until the composition root sets it (to
    /// `ShellModel.celebrate`); inject it above `.dialogHost(...)` so the dialogs, which are drawn at the window's
    /// root, see it too.
    var zentaoCelebrate: @MainActor () -> Void {
        get { self[ZentaoCelebrateKey.self] }
        set { self[ZentaoCelebrateKey.self] = newValue }
    }
}
