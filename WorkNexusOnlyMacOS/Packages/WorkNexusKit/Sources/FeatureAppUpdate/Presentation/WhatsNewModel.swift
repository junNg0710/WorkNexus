import CoreDomain
import Foundation
import Observation

/// Ported from: lib/features/app_update/presentation/widgets/whats_new_at_launch.dart (the logic half)
/// On the first launch after an update, holds what every release since the last version run brought, until the user
/// closes the dialog. A failed look is only logged: nothing for the user to act on, and it is tried again next launch.
@MainActor @Observable
public final class WhatsNewModel {
    /// Non-nil while the What's new dialog should show.
    public var news: WhatsNew?

    private let findWhatsNew: FindWhatsNew
    @ObservationIgnored private var checked = false

    public init(findWhatsNew: FindWhatsNew) { self.findWhatsNew = findWhatsNew }

    /// Looks once per launch; later calls do nothing.
    public func checkAtLaunch() async {
        guard !checked else { return }
        checked = true
        switch await findWhatsNew() {
        case .success(let found): news = found
        case .failure(let f): Diagnostics.warning("update", "What's new: \(f.message)")
        }
    }

    public func dismiss() { news = nil }
}
