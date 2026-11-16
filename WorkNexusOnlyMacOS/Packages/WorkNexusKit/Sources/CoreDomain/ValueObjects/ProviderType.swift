/// Ported from: lib/core/domain/value_objects/provider_type.dart
public enum ProviderType: String, Codable, CaseIterable, Sendable, Hashable {
    case github, gitlab, jira, zentao

    public var code: String {
        switch self { case .github: "GH"; case .gitlab: "GL"; case .jira: "JR"; case .zentao: "ZT" }
    }
    public var displayName: String {
        switch self { case .github: "GitHub"; case .gitlab: "GitLab"; case .jira: "Jira"; case .zentao: "ZenTao" }
    }
}
