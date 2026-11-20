/// Not in the Flutter app.
import CoreDomain
import Foundation

/// Why a new module's name would be refused.
public enum ZenTaoModuleNameProblem: Equatable, Sendable {
    case empty
    /// Longer than ZenTao keeps (`CheckZenTaoModuleName.maxLength`).
    case tooLong
    /// A slash separates a module from its parent in every list ZenTao gives.
    case hasSlash
    /// Its parent already has a module of that name.
    case exists
}

/// Checks the name of a module to add under `parentPath` (nil: at the top) against the module paths already there
/// ("Live stream/Share"). Names are compared as ZenTao lists them: trimmed, whatever their case.
public struct CheckZenTaoModuleName: Sendable {
    /// ZenTao's own limit for a module name.
    public static let maxLength = 60

    public init() {}

    public func callAsFunction(_ name: String, parentPath: String?, paths: [String]) -> ZenTaoModuleNameProblem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > Self.maxLength { return .tooLong }
        if trimmed.contains("/") { return .hasSlash }
        let wanted = Self.parts(parentPath ?? "") + [trimmed.lowercased()]
        return paths.contains { Self.parts($0) == wanted } ? .exists : nil
    }

    static func parts(_ path: String) -> [String] {
        path.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }
}

/// Adds a module to a ZenTao board's tree; gives back the module list with it in.
public struct AddZenTaoModule: Sendable {
    let editor: ZenTaoModuleEditor
    public init(_ editor: ZenTaoModuleEditor) { self.editor = editor }

    /// `parent`: the module to add it under (nil: at the top); `paths`: the paths of the modules already there.
    public func callAsFunction(accountId: String, rootId: String, bugs: Bool, name: String, parent: (id: String, path: String)?,
                               paths: [String]) async -> Outcome<[FormOption]> {
        if let problem = CheckZenTaoModuleName()(name, parentPath: parent?.path, paths: paths) {
            return .failure(.validation(Self.message(problem)))
        }
        return await editor.addModule(accountId: accountId, rootId: rootId, bugs: bugs,
                                      name: name.trimmingCharacters(in: .whitespacesAndNewlines), parentId: parent?.id)
    }

    static func message(_ problem: ZenTaoModuleNameProblem) -> String {
        switch problem {
        case .empty: "A module needs a name"
        case .tooLong: "A module name can be \(CheckZenTaoModuleName.maxLength) characters at most"
        case .hasSlash: "A module name cannot contain a slash"
        case .exists: "A module with this name is already there"
        }
    }
}
