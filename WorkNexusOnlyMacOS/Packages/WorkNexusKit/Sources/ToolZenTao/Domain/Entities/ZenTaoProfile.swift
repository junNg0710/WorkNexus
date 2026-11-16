import Foundation

/// Ported from: lib/tools/zentao/domain/entities/{zentao_profile,zentao_department,zentao_profile_update}.dart
public struct ZenTaoProfile: Hashable, Sendable {
    public var accountId: String
    public var account: String
    public var realname: String
    public var userId: Int?
    public var departmentId: Int?
    public var roleCode: String?
    public var avatarUrl: String?
    public var gender: String?
    public var department: String?
    public var role: String?
    public var joined: String?
    public var privilege: String?
    public var email: String?
    public var mobile: String?
    public var phone: String?
    public var wechat: String?
    public var qq: String?
    public var zipcode: String?
    public var address: String?
    public var svnGitAccount: String?
    public var skype: String?
    public var visits: Int?
    public var whatsapp: String?
    public var lastLogin: String?
    public var slack: String?
    public var lastIp: String?
    public var dingding: String?
    public init(accountId: String, account: String, realname: String) {
        self.accountId = accountId; self.account = account; self.realname = realname
    }
}

public struct ZenTaoDepartment: Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var parentId: Int
    public var path: String
    public init(id: Int, name: String, parentId: Int, path: String) {
        self.id = id; self.name = name; self.parentId = parentId; self.path = path
    }
}

public struct ZenTaoProfileUpdate: Hashable, Sendable {
    public var realname: String
    public var email: String
    public var mobile: String
    public var phone: String
    public var departmentId: Int?
    public var roleCode: String?
    public init(realname: String, email: String, mobile: String, phone: String,
                departmentId: Int? = nil, roleCode: String? = nil) {
        self.realname = realname; self.email = email; self.mobile = mobile; self.phone = phone
        self.departmentId = departmentId; self.roleCode = roleCode
    }
}
