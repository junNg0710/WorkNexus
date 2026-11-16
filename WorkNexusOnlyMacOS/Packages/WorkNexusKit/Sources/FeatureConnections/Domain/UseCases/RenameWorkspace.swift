import CoreDomain

/// Ported from: lib/features/workspace/domain/usecases/rename_workspace.dart (`RenameWorkspace`, `WorkspaceRename`)
/// A workspace and the name and badge letters it is to carry.
public struct WorkspaceRename: Sendable {
    public var workspace: Workspace
    public var name: String
    /// The letters on the badge; blank takes them from `name`.
    public var shortCode: String
    public init(workspace: Workspace, name: String, shortCode: String) {
        self.workspace = workspace; self.name = name; self.shortCode = shortCode
    }
}

/// Gives a workspace a new name and badge letters. The name is trimmed and must be there (and no longer than
/// `maxNameLength`); the letters are upper-cased, at most `maxCodeLength`, and drawn from the name when left
/// blank. The personal workspace keeps its name and may only change its letters. A refusal is a
/// `.validation` failure whose `fields` say what is wrong (`nameField` / `codeField` → `missing` / `tooLong`).
public struct RenameWorkspace: Sendable {
    public static let maxNameLength = 40
    public static let maxCodeLength = 4
    public static let nameField = "name"
    public static let codeField = "shortCode"
    public static let missing = "missing"
    public static let tooLong = "tooLong"

    public init() {}

    public func callAsFunction(_ r: WorkspaceRename) -> Outcome<Workspace> {
        var w = r.workspace
        let name = w.isPersonal ? w.name : r.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .failure(.validation("Name is required", fields: [Self.nameField: Self.missing])) }
        if name.count > Self.maxNameLength { return .failure(.validation("Name is too long", fields: [Self.nameField: Self.tooLong])) }
        let typed = r.shortCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if typed.count > Self.maxCodeLength {
            return .failure(.validation("Badge letters are too long", fields: [Self.codeField: Self.tooLong]))
        }
        w.name = name
        w.shortCode = typed.isEmpty ? Self.shortCode(of: name) : typed
        return .success(w)
    }

    /// Letters for a badge from a name: the initials of its first three words ("Company A" → "CA"), or a single
    /// word's first letters ("Acme" → "ACM").
    public static func shortCode(of name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = words.first else { return "?" }
        let code = words.count > 1 ? words.prefix(3).map { String($0.prefix(1)) }.joined() : String(first.prefix(3))
        return code.uppercased()
    }
}
