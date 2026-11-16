import CoreDomain
import Foundation
import ToolGitHub
import ToolGitLab
import ToolZenTao

/// Ported from: lib/app/di/provider_adapter_registry_impl.dart — dispatches by provider type to each tool's factory. The
/// composition root is the only place allowed to know every tool (AGENTS.md 8.1 / 8.3).
struct ProviderAdapterRegistryImpl: ProviderAdapterRegistry {
    func createAdapter(account: Account, secret: String) -> ProviderAdapter? {
        switch account.providerType {
        case .zentao: ZentaoAdapterFactory.makeAdapter(account: account, secret: secret)
        case .gitlab: GitLabAdapterFactory.make(account: account, secret: secret)
        case .github: GitHubAdapterFactory.make(account: account, secret: secret)
        case .jira: nil
        }
    }
}
