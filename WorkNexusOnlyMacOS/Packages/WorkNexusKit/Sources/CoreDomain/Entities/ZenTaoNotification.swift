import Foundation

/// Ported from: lib/features/notifications/domain/entities/zentao_notification.dart (ZenTao web bell menu).
/// e.g. "JunNg assigned Bug [#6492::Feed: video autoplay is delayed]".
public struct ZenTaoNotification: Hashable, Sendable, Identifiable {
    public var accountId: String
    public var id: String
    /// What happened, without the object link: "JunNg assigned Bug".
    public var summary: String
    /// The linked object's ZenTao type (`bug`, `task`, `story`...), lower-case.
    public var objectType: String?
    public var objectId: String?
    public var objectTitle: String?
    /// The object's page on the ZenTao server.
    public var url: String?
    public var read: Bool
    public var createdAt: Date?
    public init(accountId: String, id: String, summary: String, objectType: String? = nil, objectId: String? = nil,
                objectTitle: String? = nil, url: String? = nil, read: Bool = false, createdAt: Date? = nil) {
        self.accountId = accountId; self.id = id; self.summary = summary; self.objectType = objectType
        self.objectId = objectId; self.objectTitle = objectTitle; self.url = url; self.read = read; self.createdAt = createdAt
    }
}
