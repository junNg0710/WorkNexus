/// Not in the Flutter app.
import AppKit
import CoreDomain

public extension KeyShortcut {
    /// The keys of a key-down event; nil for an event with no key (a modifier alone).
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let code = Int(event.keyCode)
        self.init(keyCode: code, label: Self.label(keyCode: code, characters: event.charactersIgnoringModifiers ?? ""),
                  modifiers: Modifiers(event.modifierFlags))
    }

    /// What is printed on a key: its name for the keys that type nothing visible, else its character in capitals.
    static func label(keyCode: Int, characters: String) -> String {
        if let named = named[keyCode] { return named }
        if let f = functionKeyCodes.firstIndex(of: keyCode) { return "F\(f + 1)" }
        let text = characters.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return text.isEmpty ? "#\(keyCode)" : text
    }

    private static let named: [Int: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]
}

public extension KeyShortcut.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var out: KeyShortcut.Modifiers = []
        if flags.contains(.control) { out.insert(.control) }
        if flags.contains(.option) { out.insert(.option) }
        if flags.contains(.shift) { out.insert(.shift) }
        if flags.contains(.command) { out.insert(.command) }
        self = out
    }
}

/// Whether a shortcut is being chosen (`ShortcutRecorder`): the keys pressed meanwhile are the new shortcut, so nothing
/// else acts on them.
@MainActor
public enum ShortcutRecording {
    public private(set) static var isActive = false
    static func set(_ on: Bool) { isActive = on }
}
