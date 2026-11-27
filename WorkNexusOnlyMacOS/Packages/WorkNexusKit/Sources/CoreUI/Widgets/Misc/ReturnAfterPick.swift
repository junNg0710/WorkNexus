import AppKit
import SwiftUI

/// Not in the Flutter app.
/// A form whose one choice was just made is sent by Return: while `armed`, Return runs `perform` wherever the keyboard is
/// - also in a note under the choice, where it would have started a new line. Any other key, or a click, means the user
/// went on with the form: `armed` drops and Return is the field's again. `ready`: the form can be sent as it is.
public extension View {
    func returnSubmits(armed: Binding<Bool>, ready: Bool, perform: @escaping () -> Void) -> some View {
        background(ReturnAfterPickMonitor(armed: armed, ready: ready, perform: perform))
    }
}

/// What a key or a click does while a form waits for Return (`returnSubmits`).
public enum ReturnAfterPick {
    public enum Step: Equatable {
        /// Send the form; the key goes no further.
        case submit
        /// Nothing, and the key goes no further.
        case swallow
        /// The key or click is the form's, which no longer waits for Return.
        case pass
    }

    /// `plain`: no modifier is held. `isRepeat`: the key is still down from an earlier press.
    public static func step(isKey: Bool, isReturn: Bool, isRepeat: Bool, plain: Bool, ready: Bool) -> Step {
        guard isKey, isReturn, plain else { return .pass }
        // The Return that made the choice, still held: it must neither send the form nor break a line in the note.
        if isRepeat { return .swallow }
        return ready ? .submit : .pass
    }
}

private struct ReturnAfterPickMonitor: NSViewRepresentable {
    @Binding var armed: Bool
    let ready: Bool
    let perform: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.ready = ready
        view.perform = perform
        view.disarm = { armed = false }
        view.setActive(armed)
    }

    final class MonitorView: NSView {
        var ready = false
        var perform: (() -> Void)?
        var disarm: (() -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func setActive(_ on: Bool) {
            if on, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                    // Another window's (the list the choice was made in, still closing): not this form's.
                    guard let self, event.window === self.window else { return event }
                    let isKey = event.type == .keyDown
                    let step = ReturnAfterPick.step(
                        isKey: isKey, isReturn: isKey && (event.keyCode == 36 || event.keyCode == 76), isRepeat: isKey && event.isARepeat,
                        plain: event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty, ready: self.ready)
                    switch step {
                    case .swallow: return nil
                    case .pass: DispatchQueue.main.async { self.disarm?() }; return event
                    case .submit:
                        DispatchQueue.main.async { self.disarm?(); self.perform?() }
                        return nil
                    }
                }
            } else if !on, let monitor {
                NSEvent.removeMonitor(monitor); self.monitor = nil
            }
        }

        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { setActive(false) } }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
