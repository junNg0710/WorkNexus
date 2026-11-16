/// Ported from: lib/core/settings/app_settings.dart (`togglePinnedProject`, `togglePinnedExecution`)
import CoreDomain
import Foundation

extension ZentaoUIState {
    /// Pins / unpins product `productId` of `accountId`. The boards watch the settings, so the rows follow once the
    /// write lands.
    func togglePinnedProduct(accountId: String, productId: String) {
        let key = ZentaoNavLogic.productKey(accountId: accountId, productId: productId)
        let settings = deps.services.settings
        Task {
            var s = await settings.load()
            s.pinnedProjects = ZentaoNavLogic.toggled(s.pinnedProjects, key)
            _ = await settings.save(s)
        }
    }

    /// Pins / unpins execution `executionId` of `accountId`.
    func togglePinnedExecution(accountId: String, executionId: String) {
        let key = ZentaoNavLogic.executionKey(accountId: accountId, executionId: executionId)
        let settings = deps.services.settings
        Task {
            var s = await settings.load()
            s.pinnedExecutions = ZentaoNavLogic.toggled(s.pinnedExecutions, key)
            _ = await settings.save(s)
        }
    }
}
