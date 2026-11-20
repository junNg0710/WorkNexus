import Foundation

/// What the work tracker knows about a person beyond chat: their place in the organisation and how to reach them. Every
/// field is optional: servers and privileges differ in what they share.
/// Ported from: lib/core/domain/entities/person_profile.dart
public struct PersonProfile: Equatable, Sendable {
    /// Readable department path, e.g. "VN > Flutter VN".
    public var department: String?
    /// Role code (`dev`, `qa`…) or name, as the server sends it.
    public var role: String?
    public var email: String?
    public var mobile: String?
    public var phone: String?
    public var gender: String?
    public var address: String?
    public var joined: Date?
    public var lastLogin: Date?
    /// Messenger handles.
    public var wechat: String?
    public var qq: String?
    public var skype: String?
    public var slack: String?
    public var whatsapp: String?
    public var dingding: String?

    public init(department: String? = nil, role: String? = nil, email: String? = nil, mobile: String? = nil, phone: String? = nil,
                gender: String? = nil, address: String? = nil, joined: Date? = nil, lastLogin: Date? = nil, wechat: String? = nil,
                qq: String? = nil, skype: String? = nil, slack: String? = nil, whatsapp: String? = nil, dingding: String? = nil) {
        self.department = department; self.role = role; self.email = email; self.mobile = mobile; self.phone = phone
        self.gender = gender; self.address = address; self.joined = joined; self.lastLogin = lastLogin; self.wechat = wechat
        self.qq = qq; self.skype = skype; self.slack = slack; self.whatsapp = whatsapp; self.dingding = dingding
    }
}

/// Looks up a colleague on the work tracker behind an account (ZenTao today). Shared kernel: chat asks, the tracker answers,
/// neither imports the other.
/// Ported from: lib/core/domain/repositories/person_directory.dart
public protocol PersonDirectory: Sendable {
    /// The profile of user `userId` (the tracker's user id, which is the chat user id) as account `accountId` may see it.
    func lookup(accountId: String, userId: Int) async -> Outcome<PersonProfile>
}
