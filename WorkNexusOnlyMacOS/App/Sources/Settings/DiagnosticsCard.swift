import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import UniformTypeIdentifiers

/// The diagnostics log in Local data (not in the Flutter app): what it keeps, how big it is, and the ways to look at it,
/// send it with a bug report, or empty it.
struct DiagnosticsCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let log: FileDiagnosticsLog
    @State private var bytes = 0
    @State private var performance = DiagnosticsWiring.performanceLogOn
    @State private var showFps = DiagnosticsWiring.showFpsOn

    var body: some View {
        SettingsCard(title: appString("diagnosticsTitle", "Diagnostics"),
                     subtitle: appString("diagnosticsHint", "Errors and the steps before them are kept on this Mac for 7 days, to trace problems. Nothing is sent anywhere. Passwords, tokens and the text of messages and tickets are never recorded.")) {
            SettingsRow(label: appString("diagnosticsLogs", "Error log"), hint: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) {
                HStack(spacing: theme.spacing.s8) {
                    AppButton(appString("diagnosticsOpen", "Open folder"), systemImage: "folder", kind: .ghost) {
                        log.flush(); NSWorkspace.shared.open(log.directory)
                    }
                    AppButton(appString("diagnosticsExport", "Export…"), systemImage: "square.and.arrow.up", action: export)
                    AppButton(appString("diagnosticsClear", "Clear"), kind: .ghost) {
                        log.clear(); refresh()
                        toasts?.show(appString("diagnosticsCleared", "Error log cleared"))
                    }
                }
            }
            SettingsToggleRow(label: appString("diagnosticsPerformance", "Performance log"),
                              hint: appString("diagnosticsPerformanceHint", "While on, stutters (a scroll that jerks, a frame drawn late) and slow work (opening a chat, loading older messages, decoding pictures) are written to the log with where they happened. Turn it on to trace lag, then export the log. Uses a little more power."),
                              isOn: performance) { on in
                performance = on
                DiagnosticsWiring.setPerformanceLog(on)
                toasts?.show(on ? appString("diagnosticsPerformanceOn", "Performance log on") : appString("diagnosticsPerformanceOff", "Performance log off"))
            }
            SettingsToggleRow(label: appString("diagnosticsFps", "Show FPS"),
                              hint: appString("diagnosticsFpsHint", "Shows a small badge in the bottom corner of the window: the frames drawn in the last second and the longest wait between two of them. Green is smooth, amber uneven, red slow. Uses a little more power while on."),
                              isOn: showFps) { on in
                showFps = on
                DiagnosticsWiring.setShowFps(on)
            }
        }
        .task { refresh() }
    }

    private func refresh() { log.flush(); bytes = log.totalBytes() }

    /// Saves the logs and a description of this Mac as one zip, to attach to a bug report.
    private func export() {
        log.flush()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.omitted))
        panel.nameFieldStringValue = "WorkNexus-diagnostics-\(stamp).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagnosticsArchive.export(logs: log.files(), about: DiagnosticsArchive.about(), to: url)
            toasts?.show(appString("diagnosticsExported", "Diagnostics saved"))
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            toasts?.show(appFormat("diagnosticsExportFailed", "Couldn't save the diagnostics: %1$@", error.localizedDescription), kind: .error)
        }
    }
}
