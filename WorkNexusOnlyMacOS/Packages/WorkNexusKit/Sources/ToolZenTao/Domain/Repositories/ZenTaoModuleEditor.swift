/// Not in the Flutter app.
import CoreDomain
import Foundation

/// The modules of a ZenTao board - a product's (bugs) or an execution's (tasks) - and adding one.
public protocol ZenTaoModuleEditor: Sendable {
    /// Adds module `name` to product `rootId`'s bug modules (`bugs`) or execution `rootId`'s task modules, under module
    /// `parentId` (nil: at the top). Returns the module list as ZenTao has it afterwards (id and path, in its order).
    func addModule(accountId: String, rootId: String, bugs: Bool, name: String, parentId: String?) async -> Outcome<[FormOption]>
}

/// No module can be added (previews, tests).
public struct NoZenTaoModuleEditor: ZenTaoModuleEditor {
    public init() {}
    public func addModule(accountId: String, rootId: String, bugs: Bool, name: String, parentId: String?) async -> Outcome<[FormOption]> {
        .failure(.unexpected("Modules cannot be added here"))
    }
}
