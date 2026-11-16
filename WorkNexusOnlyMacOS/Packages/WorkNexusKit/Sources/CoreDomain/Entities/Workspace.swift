/// Ported from: lib/core/domain/entities/workspace.dart (+ project.dart)
public struct Workspace: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var shortCode: String
    public var colorValue: Int
    public var iconKey: String
    public var isPersonal: Bool
    public init(id: String, name: String, shortCode: String, colorValue: Int,
                iconKey: String = "briefcase", isPersonal: Bool = false) {
        self.id = id; self.name = name; self.shortCode = shortCode; self.colorValue = colorValue
        self.iconKey = iconKey; self.isPersonal = isPersonal
    }
}

public struct Project: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var accountId: String
    public var name: String
    public var externalId: String?
    public init(id: String, accountId: String, name: String, externalId: String? = nil) {
        self.id = id; self.accountId = accountId; self.name = name; self.externalId = externalId
    }
}
