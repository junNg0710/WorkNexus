/// Not in the Flutter app.
/// The models offered for Claude Code: its aliases for the latest model of each tier ("" = Claude Code's own default). The
/// user may type a full model name instead.
public enum ClaudeCodeModels {
    public static let aliases = ["haiku", "sonnet", "opus"]

    /// The entries of the model dropdown: the default, the aliases, and a typed model that is none of them.
    public static func choices(selected: String) -> [String] {
        let s = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        return [""] + aliases + (s.isEmpty || aliases.contains(s) ? [] : [s])
    }
}
