import AppKit
import Foundation

/// DEBUG builds only: `WN_DEMO_TYPE=<seconds>:<text>[|<seconds>:<text>…]` types each text into whatever has the keyboard
/// in the main window, that many seconds after launch, one key at a time as the keyboard would - to try a search field in
/// a demo run without a hand on the keyboard (`WN_DEMO_KEYS=40+cmd` presses ⌘K first, `WN_DEMO_CLICK` clicks a field).
enum DemoType {
    @MainActor
    static func start() {
        #if DEBUG
        guard let spec = ProcessInfo.processInfo.environment["WN_DEMO_TYPE"] else { return }
        for part in spec.split(separator: "|") {
            guard let colon = part.firstIndex(of: ":"), let at = Double(part[..<colon]) else { continue }
            let text = String(part[part.index(after: colon)...])
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(at))
                for c in text {
                    guard let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }),
                          let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: w.windowNumber, context: nil, characters: String(c),
                                                   charactersIgnoringModifiers: String(c), isARepeat: false, keyCode: 0) else { continue }
                    NSApp.postEvent(e, atStart: false)
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
        }
        #endif
    }
}
