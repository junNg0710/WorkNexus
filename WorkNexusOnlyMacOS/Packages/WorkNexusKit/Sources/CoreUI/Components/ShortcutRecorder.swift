/// Not in the Flutter app.
import AppKit
import CoreDomain
import SwiftUI

/// Shows a keyboard shortcut and lets the user choose another: a click starts listening, the next key combination is the
/// new shortcut (`problem` may refuse it, saying why), Delete removes it and Esc - or a click anywhere - leaves it as it was.
public struct ShortcutRecorder: View {
    @Environment(\.appTheme) private var theme
    let shortcut: KeyShortcut?
    /// Why these keys cannot be used, as a line for the user; nil when they can.
    let problem: (KeyShortcut) -> String?
    let onChange: (KeyShortcut?) -> Void
    @State private var recording = false
    @State private var refused: String?

    public init(shortcut: KeyShortcut?, problem: @escaping (KeyShortcut) -> String? = { _ in nil }, onChange: @escaping (KeyShortcut?) -> Void) {
        self.shortcut = shortcut; self.problem = problem; self.onChange = onChange
    }

    public var body: some View {
        HStack(spacing: theme.spacing.s6) {
            if recording, let refused { Text(refused).font(theme.typography.caption).foregroundStyle(theme.colors.red) }
            Button { recording.toggle(); refused = nil } label: {
                Text(recording ? appString("shortcutRecording", "Press the keys…") : shortcut?.display ?? appString("shortcutNone", "None"))
                    .font(recording || shortcut == nil ? theme.typography.meta : theme.typography.bodyStrong)
                    .foregroundStyle(recording ? theme.colors.accent : (shortcut == nil ? theme.colors.tx3 : theme.colors.tx))
                    .padding(.horizontal, theme.spacing.s10).frame(minWidth: theme.sizes.control36 * 2, minHeight: theme.sizes.control32)
                    .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md)
                        .stroke(recording ? theme.colors.accent : theme.colors.line, lineWidth: theme.borders.hairline))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerStyle(.link)
            .help(appString("shortcutChangeHelp", "Click, then press the new keys. Delete removes the shortcut, Esc cancels."))
            .background { if recording { ShortcutKeyCapture(onKeys: take, onCancel: { recording = false }) } }
        }
    }

    private func take(_ keys: KeyShortcut) {
        // Esc leaves it as it was; Delete (with nothing held) removes it.
        if keys.modifiers.isEmpty, keys.keyCode == 53 { recording = false; return }
        if keys.modifiers.isEmpty, keys.keyCode == 51 || keys.keyCode == 117 { recording = false; onChange(nil); return }
        if let why = problem(keys) { refused = why; return }
        recording = false
        onChange(keys)
    }
}

/// Takes every key pressed while it is in a window (nothing else sees them) and ends on a click anywhere.
private struct ShortcutKeyCapture: NSViewRepresentable {
    let onKeys: (KeyShortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) { view.onKeys = onKeys; view.onCancel = onCancel }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.stop() }

    final class CaptureView: NSView {
        var onKeys: (KeyShortcut) -> Void = { _ in }
        var onCancel: () -> Void = {}
        private var token: Any?

        override func viewDidMoveToWindow() {
            stop()
            guard window != nil else { return }
            ShortcutRecording.set(true)
            token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                // A click ends the listening and goes on to what was clicked (the same field again closes it there).
                // After the click is handled: a click on the field itself already stops the listening.
                guard event.type == .keyDown else { DispatchQueue.main.async { [weak self] in self?.onCancel() }; return event }
                if let keys = KeyShortcut(event: event) { self.onKeys(keys) }
                return nil
            }
        }

        func stop() {
            guard let token else { return }
            NSEvent.removeMonitor(token)
            self.token = nil
            ShortcutRecording.set(false)
        }
    }
}
