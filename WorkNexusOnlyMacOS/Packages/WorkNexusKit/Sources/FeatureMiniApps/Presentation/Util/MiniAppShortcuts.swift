import AppKit
import Foundation

/// What a browser key does to a mini app's page or tabs.
enum MiniAppShortcut: Equatable {
    case reload, hardReload, back, forward, home, focusAddress, devTools
    case newTab, closeTab, nextTab, previousTab
}

/// Ported from: lib/features/mini_apps/presentation/util/mini_app_shortcuts.dart
/// The browser's usual keys for a mini app: ⌘R / F5 reload, ⇧⌘R / ⌃F5 reload from the origin, ⌘L / F6 the address,
/// ⇧⌘I / F12 the inspector, ⌥← / ⌥→ back and forward, ⌥Home home — and the tabs': ⌘T new, ⌘W close, ⇧⌘[ / ⇧⌘] and
/// ⌃Tab / ⌃⇧Tab to switch. (⌘[ and ⌘] go back and forward too.) Esc is left to the page, which often uses it.
/// A pure mapping so it can be tested; `MiniAppKeyMonitor` feeds it the key events.
func miniAppShortcut(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> MiniAppShortcut? {
    let mods = modifiers.intersection([.command, .control, .option, .shift])
    let key = characters.lowercased()
    switch (mods, keyCode) {
    case ([], 96): return .reload                       // F5
    case ([.control], 96): return .hardReload
    case ([], 97): return .focusAddress                 // F6
    case ([], 111): return .devTools                    // F12
    case ([.option], 123): return .back
    case ([.option], 124): return .forward
    case ([.option], 115): return .home
    case ([.control], 48): return .nextTab              // Tab
    case ([.control, .shift], 48): return .previousTab
    default: break
    }
    guard mods.contains(.command), mods.isDisjoint(with: [.control, .option]) else { return nil }
    let shift = mods.contains(.shift)
    switch key {
    case "r": return shift ? .hardReload : .reload
    case "l": return shift ? nil : .focusAddress
    case "i": return shift ? .devTools : nil
    case "t": return shift ? nil : .newTab
    case "w": return shift ? nil : .closeTab
    case "[": return shift ? .previousTab : .back
    case "]": return shift ? .nextTab : .forward
    // ⇧⌘[ and ⇧⌘] type `{` and `}` on a US keyboard.
    case "{": return .previousTab
    case "}": return .nextTab
    default: return nil
    }
}
