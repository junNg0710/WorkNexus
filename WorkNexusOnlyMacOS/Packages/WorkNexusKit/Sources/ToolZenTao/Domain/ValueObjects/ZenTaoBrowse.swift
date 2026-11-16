import Foundation

/// Ported from: lib/tools/zentao/domain/value_objects/{zentao_bug_browse_type,zentao_bug_stream}.dart
/// The ZenTao "browse type" tabs for a product's bug board, in tab-strip order (`unclosed` is the default).
public enum ZenTaoBugBrowseType: String, CaseIterable, Sendable, Hashable {
    case all, unclosed, reportedByMe, relatedToMe, resolvedByMe, assignedByMe

    /// The literal value ZenTao's bug-list API expects for this view.
    public var code: String {
        switch self {
        case .all: "all"
        case .unclosed: "unclosed"
        case .reportedByMe: "openedbyme"
        case .relatedToMe: "assigntome"
        case .resolvedByMe: "resolvedbyme"
        case .assignedByMe: "assignedbyme"
        }
    }
}

/// A ZenTao server-side bug view that the bug board pages on its own.
public enum ZenTaoBugStream: String, CaseIterable, Sendable, Hashable {
    case unconfirmed, unresolved, toClose, all, relatedToMe

    /// The literal browse type ZenTao's bug-list API expects.
    public var code: String {
        switch self {
        case .unconfirmed: "unconfirmed"
        case .unresolved: "unresolved"
        case .toClose: "toclosed"
        case .all: "all"
        case .relatedToMe: "assigntome"
        }
    }
    /// Further browse types fetched alongside `code` and merged into this view.
    public var also: [String] { self == .relatedToMe ? ["openedbyme", "resolvedbyme"] : [] }
    /// Every browse type this view is made of.
    public var codes: [String] { [code] + also }

    /// The view `column` draws its bugs from; `relatedToMe` for every column on the Related-to-me tab.
    public static func of(_ column: ZenTaoBugColumn, related: Bool = false) -> ZenTaoBugStream {
        if related { return .relatedToMe }
        switch column {
        case .newUnconfirmed: return .unconfirmed
        case .confirmedToFix: return .unresolved
        case .resolvedVerify, .postponed, .nonFix: return .toClose
        case .closed: return .all
        }
    }
}
