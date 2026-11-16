import CoreTools
import FeatureWorkspaceOverview
import Observation

/// The overview model of the *active* workspace. `OverviewModel` takes its workspace at construction, so when the user
/// switches workspace the holder builds a new one for it (the old one stops); the workspace page reads `model` in a view
/// body, so it follows.
@MainActor @Observable
final class OverviewHolder {
    private(set) var model: OverviewModel
    private(set) var workspaceId: String?
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let nav: AppNavController
    @ObservationIgnored private let registry: ToolRegistry

    init(services: AppServices, nav: AppNavController, registry: ToolRegistry, workspaceId: String?) {
        self.services = services; self.nav = nav; self.registry = registry; self.workspaceId = workspaceId
        model = WorkspaceOverviewFeature.make(services: services, nav: nav, registry: registry, activeWorkspaceId: workspaceId)
    }

    func start() { model.start() }

    /// Follows the shell: a different active workspace gets its own overview model.
    func follow(workspaceId id: String?) {
        guard id != workspaceId else { return }
        workspaceId = id
        model.stop()
        model = WorkspaceOverviewFeature.make(services: services, nav: nav, registry: registry, activeWorkspaceId: id)
        model.start()
    }
}
