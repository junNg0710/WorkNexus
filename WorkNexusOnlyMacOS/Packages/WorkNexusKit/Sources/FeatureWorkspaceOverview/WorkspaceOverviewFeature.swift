import CoreTools
import Foundation

/// Public entry point of FeatureWorkspaceOverview. The composition root builds one `WorkspaceOverviewFeature.make(...)`,
/// calls `model.start()` and places `WorkspaceOverviewHost(model:accounts:)` in the workspace rail's content.
public enum WorkspaceOverviewFeature {
    public static let name = "FeatureWorkspaceOverview"

    /// The production wiring: everything read from / driven through `services`.
    @MainActor
    public static func make(services: AppServices, nav: AppNavController, registry: ToolRegistry,
                            activeWorkspaceId: String? = nil) -> OverviewModel {
        OverviewModel(repository: ServicesOverviewRepository(services: services), nav: nav, registry: registry,
                      activeWorkspaceId: activeWorkspaceId)
    }
}
