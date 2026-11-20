/// Not in the Flutter app.
import CoreDomain
import CoreUI
import Foundation
import Observation
import SwiftUI

/// What the bulk assign dialog has typed: a note and hours for every ticket, and each ticket's own.
@MainActor @Observable
final class ZentaoBulkAssignForm {
    var sharedNoteText = ""
    var sharedHoursText = ""
    /// By ticket id.
    var notes: [String: String] = [:]
    var hours: [String: String] = [:]

    var sharedNote: String? { Self.text(sharedNoteText) }
    var sharedHours: Double? { Self.hours(sharedHoursText) }

    /// Each ticket's own note and hours, where something valid was typed.
    var details: [String: ZenTaoAssignDetail] {
        var out: [String: ZenTaoAssignDetail] = [:]
        for id in Set(notes.keys).union(hours.keys) {
            let detail = ZenTaoAssignDetail(comment: Self.text(notes[id] ?? ""), left: Self.hours(hours[id] ?? ""))
            if detail.comment != nil || detail.left != nil { out[id] = detail }
        }
        return out
    }

    func note(_ id: String) -> Binding<String> { Binding(get: { self.notes[id] ?? "" }, set: { self.notes[id] = $0 }) }
    func hoursText(_ id: String) -> Binding<String> { Binding(get: { self.hours[id] ?? "" }, set: { self.hours[id] = $0 }) }

    /// Why typed hours would be refused, or nil (nothing typed is fine).
    static func problem(_ text: String) -> ZenTaoTaskInputProblem? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : CheckZenTaoAssignLeft()(zentaoParseHours(text))
    }

    private static func text(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func hours(_ s: String) -> Double? {
        let h = zentaoParseHours(s)
        return CheckZenTaoAssignLeft()(h) == nil ? h : nil
    }
}

/// A one-line field of the bulk dialog with a placeholder; `digits` keeps only a number of hours; `warn` rings it red.
struct ZentaoBulkField: View {
    @Environment(\.appTheme) private var theme
    @Binding var text: String; let prompt: String
    var digits = false; var warn = false

    var body: some View {
        let c = theme.colors
        TextField("", text: $text, prompt: Text(prompt).foregroundStyle(c.tx3))
            .textFieldStyle(.plain).font(theme.typography.body).foregroundStyle(c.tx)
            .onChange(of: text) { _, new in
                guard digits else { return }
                let kept = new.filter { "0123456789.,".contains($0) }
                if kept != new { text = kept }
            }
            .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control32)
            .background(c.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(warn ? c.red : c.line, lineWidth: theme.borders.hairline))
    }
}

/// The note for every ticket and the hours for every task that has none; a ticket's own row wins over them.
struct ZentaoBulkShared: View {
    @Environment(\.appTheme) private var theme
    @Bindable var form: ZentaoBulkAssignForm
    let tasksWithoutHours: Int

    var body: some View {
        // Fields on one line whatever their labels take (a long one wraps above its field); a problem goes under both.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: theme.spacing.s10) {
                if tasksWithoutHours > 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        ZentaoFieldLabel(appFormat("leaderBulkHoursLeft", "Hours left, for the %1$@ tasks that have none", "\(tasksWithoutHours)"))
                        ZentaoBulkField(text: $form.sharedHoursText, prompt: appString("zentaoHoursLeft", "Hours left"), digits: true,
                                        warn: ZentaoBulkAssignForm.problem(form.sharedHoursText) != nil)
                    }
                    .frame(maxWidth: theme.sizes.toolPaneCompact)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ZentaoFieldLabel(appString("leaderBulkNoteAll", "Note for every ticket"))
                    ZentaoBulkField(text: $form.sharedNoteText, prompt: appString("taskDetailNoteHint", "Optional note…"))
                }
            }
            if tasksWithoutHours > 0, let problem = ZentaoBulkAssignForm.problem(form.sharedHoursText) { ZentaoTaskProblemLine(problem) }
        }
    }
}
