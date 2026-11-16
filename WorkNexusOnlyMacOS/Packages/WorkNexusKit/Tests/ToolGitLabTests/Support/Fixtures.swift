import CoreDomain
import Foundation
@testable import ToolGitLab

enum Fixtures {
    static func ticket(type: String, key: String = "42", status: UnifiedStatus = .review, providerStatus: String = "opened",
                       priority: Priority = .medium, id: String = "gl-a:x", accountId: String = "gl-a",
                       projectId: String = "gl-a:group/web", updatedAt: Date? = nil, title: String = "t") -> Ticket {
        Ticket(id: id, accountId: accountId, projectId: projectId, providerType: .gitlab, externalKey: key, title: title,
               body: "", priority: priority, status: status, providerStatus: providerStatus, sourceHash: "h",
               externalType: type, updatedAt: updatedAt)
    }

    static func client(_ net: StubNetwork = .shared) -> GitLabClient {
        GitLabClient(baseUrl: "https://gitlab.example.com", token: "pat123", session: net.session)
    }

    static func adapter(_ net: StubNetwork = .shared, rebasePollInterval: Duration = .zero) -> GitLabProviderAdapter {
        GitLabProviderAdapter(accountId: "gl-a", client: client(net), rebasePollInterval: rebasePollInterval)
    }
}
