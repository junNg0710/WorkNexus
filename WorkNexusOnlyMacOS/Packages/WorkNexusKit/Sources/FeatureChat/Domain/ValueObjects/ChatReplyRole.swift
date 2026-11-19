/// Not in the Flutter app.
/// Who the user is in the team, so the AI's reply ideas sound like them: a tech lead decides and unblocks, a developer talks
/// implementation and status, a tester talks reproduction and verification. `.auto` takes the role ZenTao gives the account.
public enum ChatReplyRole: String, Sendable, CaseIterable, Codable {
    case auto, techLead, developer, tester, projectManager, productOwner, designer, businessAnalyst

    /// The roles the user can pick (everything but `.auto`).
    public static var picks: [ChatReplyRole] { allCases.filter { $0 != .auto } }

    /// The role behind a ZenTao role code (`dev`, `qa`, `pm`, `po`, `td`, …); nil for a code with no clear voice.
    public static func fromZenTao(_ code: String?) -> ChatReplyRole? {
        switch code?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "td", "tl", "lead", "techlead": .techLead
        case "dev", "developer": .developer
        case "qa", "qd", "test", "tester": .tester
        case "pm", "top": .projectManager
        case "po", "pd": .productOwner
        case "ui", "ux", "design", "designer": .designer
        case "ba": .businessAnalyst
        default: nil
        }
    }

    /// The role in English, for the prompt.
    public var englishName: String {
        switch self {
        case .auto: "team member"
        case .techLead: "tech lead"
        case .developer: "developer"
        case .tester: "QA tester"
        case .projectManager: "project manager"
        case .productOwner: "product owner"
        case .designer: "UI/UX designer"
        case .businessAnalyst: "business analyst"
        }
    }

    /// How someone in this role writes in a team chat: what the reply ideas should sound like.
    public var voice: String {
        switch self {
        case .auto: "a member of the team"
        case .techLead:
            "the tech lead: decides and gives direction, sets priorities, unblocks people, assigns an owner and a deadline, asks "
                + "about risks, estimates and the technical approach, and reviews before things ship"
        case .developer:
            "a developer: concrete about the implementation and its status (done, in progress, blocked), mentions the branch, "
                + "merge request or build, asks precise questions about requirements, and gives realistic estimates"
        case .tester:
            "a QA tester: precise about the bug — steps to reproduce, expected vs. actual result, environment, build or app "
                + "version, device — gives ticket numbers, and confirms whether a fix is verified or still fails"
        case .projectManager:
            "the project manager: keeps the plan on track — deadlines, scope, priorities, who does what — follows up on open "
                + "items, and asks for status or a date"
        case .productOwner:
            "the product owner: speaks for the users and the requirements, clarifies expected behaviour and acceptance "
                + "criteria, and decides on scope and priority"
        case .designer:
            "a UI/UX designer: talks layout, spacing, colours, flows and the design file, and checks the build against the design"
        case .businessAnalyst:
            "a business analyst: clarifies requirements and business rules, edge cases and acceptance criteria"
        }
    }
}

/// The voice the AI writes reply ideas in: the role the user picked, else the one ZenTao gives the account (a known code,
/// or at least its name), else none.
public struct ResolveReplyRole: Sendable {
    public init() {}

    /// - Parameters:
    ///   - picked: the setting (`.auto` follows ZenTao).
    ///   - zenTaoRole: the account's role code; `roleName` its display name from the server, for a code without a known voice.
    public func callAsFunction(_ picked: ChatReplyRole, zenTaoRole: String?, roleName: String?) -> String? {
        if picked != .auto { return picked.voice }
        if let known = ChatReplyRole.fromZenTao(zenTaoRole) { return known.voice }
        let name = (roleName ?? zenTaoRole ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : "a \(name) in a software team"
    }
}
