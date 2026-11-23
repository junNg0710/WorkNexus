import AppKit
import SharedKit

/// DEBUG builds only: `WN_DEMO_KEYS=<key code>[+cmd][+ctrl][+opt][+shift],…` presses those keys in the main window, one every
/// two seconds from the sixth, as the keyboard would (they go through the app's event queue, so the monitors see them), and
/// prints the place on screen after each - to try the rail's keyboard shortcuts without a hand on the keyboard.
/// `flags[+cmd]…` instead of a key code holds just those modifiers down (none: lets them go), as for the rail's key hints.
enum DemoKeys {
    @MainActor
    static func start(shell: ShellModel) {
        #if DEBUG
        guard let spec = ProcessInfo.processInfo.environment["WN_DEMO_KEYS"] else { return }
        let presses = spec.split(separator: ",").compactMap { raw -> (UInt16?, NSEvent.ModifierFlags)? in
            let parts = raw.split(separator: "+")
            let code = parts.first.flatMap { UInt16($0) }
            guard code != nil || parts.first == "flags" else { return nil }
            var flags: NSEvent.ModifierFlags = []
            for p in parts.dropFirst() {
                switch p { case "cmd": flags.insert(.command); case "ctrl": flags.insert(.control)
                case "opt": flags.insert(.option); case "shift": flags.insert(.shift); default: break }
            }
            return (code, flags)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            for (code, flags) in presses {
                if let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }),
                   let e = NSEvent.keyEvent(with: code == nil ? .flagsChanged : .keyDown, location: .zero, modifierFlags: flags,
                                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil,
                                            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code ?? 55) {
                    NSApp.postEvent(e, atStart: false)
                }
                try? await Task.sleep(for: .seconds(1))
                print("DEMOKEYS \(code.map(String.init) ?? "flags") \(flags.rawValue): rail \(shell.nav.state.rail), mini app \(shell.nav.state.miniAppId ?? "-"), hints \(shell.railHints.held.map { String($0.rawValue) } ?? "-")"); fflush(stdout)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        #endif
    }
}
