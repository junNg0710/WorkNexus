/// How much of a chat's message list is shown while it opens. Opening a chat built its header, composer, wallpaper and
/// first screen of message rows in one frame, which held the window up for a tenth of a second on every switch; shown in
/// stages, a frame apart, each frame does a part of it: first the chat without its messages, then the newest few
/// (they sit at the bottom, where the list opens), then all.
enum ChatOpeningStage: Equatable {
    case chrome
    case newest
    case all

    /// Rows shown in the `newest` stage: about half a screen of messages.
    static let newestCount = 6

    /// The stage after this one.
    var next: ChatOpeningStage {
        switch self {
        case .chrome: .newest
        case .newest, .all: .all
        }
    }

    var showsList: Bool { self != .chrome }

    /// The rows to show of `rows` (oldest first) at this stage.
    func shown(_ rows: [ChatListRow]) -> ArraySlice<ChatListRow> {
        switch self {
        case .chrome: rows.prefix(0)
        case .newest: rows.suffix(Self.newestCount)
        case .all: rows[...]
        }
    }
}
