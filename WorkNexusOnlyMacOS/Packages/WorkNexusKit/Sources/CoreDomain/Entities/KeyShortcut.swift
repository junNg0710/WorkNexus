/// Not in the Flutter app.
import Foundation

/// A key pressed with its modifiers: what a keyboard shortcut is made of. The key is the one on the keyboard (`keyCode`), so
/// it is the same key whatever the input method types with it; `label` is what is printed on it, for showing.
public struct KeyShortcut: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    public var keyCode: Int
    public var label: String
    public var modifiers: Modifiers

    public init(keyCode: Int, label: String, modifiers: Modifiers) {
        self.keyCode = keyCode; self.label = label; self.modifiers = modifiers
    }

    /// The same keys, whatever is printed on them.
    public static func == (a: KeyShortcut, b: KeyShortcut) -> Bool { a.keyCode == b.keyCode && a.modifiers == b.modifiers }
    public func hash(into hasher: inout Hasher) { hasher.combine(keyCode); hasher.combine(modifiers) }

    /// As macOS writes it in a menu: ⌃⌥⇧⌘ then the key.
    public var display: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        return out + label
    }

    /// The keys F1 … F20, in order: the only ones that make a shortcut with no ⌘ or ⌃ held.
    public static let functionKeyCodes = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
    public var isFunctionKey: Bool { Self.functionKeyCodes.contains(keyCode) }

    /// The key codes of the digits 1 … 9 and 0 on the top row, as they sit on it.
    public static let digitKeyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]

    /// The keys of the `n`-th place from the top when none were chosen: ⌘1 … ⌘9 and ⌘0 for the first ten, ⌥⌘1 … ⌥⌘0 for
    /// the next ten; nil beyond.
    public static func byPosition(_ n: Int) -> KeyShortcut? {
        guard (1...20).contains(n) else { return nil }
        let digit = (n - 1) % 10
        return KeyShortcut(keyCode: digitKeyCodes[digit], label: String((digit + 1) % 10), modifiers: n <= 10 ? .command : [.command, .option])
    }

    /// What a place shows while `held` is down: the rest of its shortcut (`1` while ⌘ is held for ⌘1, `⌥1` for ⌥⌘1); nil
    /// when the shortcut is not made with those modifiers.
    public func hint(whileHolding held: Modifiers) -> String? {
        guard !held.isEmpty, modifiers.isSuperset(of: held) else { return nil }
        return KeyShortcut(keyCode: keyCode, label: label, modifiers: modifiers.subtracting(held)).display
    }
}

/// Why a key combination cannot be a shortcut for a place.
public enum KeyShortcutProblem: Equatable, Sendable {
    /// A plain key (or one with only ⇧ / ⌥) would be typed into every text field.
    case needsCommandOrControl
    /// The app's menus already use it (⌘C, ⌘K, ⌘W …).
    case reserved
}

public extension KeyShortcut {
    /// ⌘ with these keys belongs to the app's menus and to editing text (with or without ⇧).
    private static let menuKeyCodes: Set<Int> = [
        12, 13, 4, 46, 43, 45, 40, 15, 8, 9, 7, 0, 6, 3, 1, 17, 37, 33, 30, 35, 31, 50, 48, 49, 53, 36,
    ]

    /// Whether these keys can open a place, and why not.
    var problem: KeyShortcutProblem? {
        if !isFunctionKey, modifiers.isDisjoint(with: [.command, .control]) { return .needsCommandOrControl }
        if modifiers.contains(.command), modifiers.isDisjoint(with: [.control, .option]), Self.menuKeyCodes.contains(keyCode) { return .reserved }
        return nil
    }
}
