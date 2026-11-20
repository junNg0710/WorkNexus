/// Ported from: lib/features/chat/presentation/widgets/chat_summary_view.dart
import AppKit
import CoreUI
import SwiftUI

/// An AI summary of a chat, section by section; empty sections are left out. Its text can be selected or copied whole.
struct ChatSummaryView: View {
    @Environment(\.appTheme) private var theme
    @State private var copied = false
    let summary: ChatSummary

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s16) {
            if !summary.overview.isEmpty {
                SummarySection(title: ChatSummaryText.overview, systemImage: "text.bubble") {
                    Text(summary.overview).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
                }
            }
            BulletSection(title: ChatSummaryText.keyPoints, systemImage: "sparkle", lines: summary.keyPoints)
            BulletSection(title: ChatSummaryText.decisions, systemImage: "checkmark.seal", lines: summary.decisions)
            if !summary.actionItems.isEmpty {
                SummarySection(title: ChatSummaryText.actionItems, systemImage: "checklist") {
                    ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in ActionItemRow(item: item) }
                }
            }
            BulletSection(title: ChatSummaryText.openQuestions, systemImage: "questionmark.circle", lines: summary.openQuestions)
            VStack(alignment: .leading, spacing: theme.spacing.s4) {
                HStack {
                    Text(copied ? appString("chatAiSummaryCopied", "Summary copied") : footer)
                        .font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
                    Spacer(minLength: theme.spacing.s8)
                    AppIconButton(copied ? "checkmark" : "doc.on.doc", help: appString("chatAiCopySummary", "Copy summary")) { copy() }
                }
                Text(appString("chatAiNote", "Written by AI from the messages · check before relying on it"))
                    .font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
            }
        }
        .textSelection(.enabled)
    }

    private var footer: String {
        let count = "\(summary.messageCount)"
        guard let model = summary.model else { return appFormat("chatAiSummaryFooterNoModel", "%1$@ messages summarized", count) }
        return appFormat("chatAiSummaryFooter", "%1$@ messages · %2$@", count, model)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ChatSummaryText.plain(summary), forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}

/// The summary's section titles, and the whole summary as plain text to paste into a ticket or another chat.
enum ChatSummaryText {
    static var overview: String { appString("chatAiOverview", "Overview") }
    static var keyPoints: String { appString("chatAiKeyPoints", "Key points") }
    static var decisions: String { appString("chatAiDecisions", "Decisions") }
    static var actionItems: String { appString("chatAiActionItems", "Action items") }
    static var openQuestions: String { appString("chatAiOpenQuestions", "Open questions") }
    static func due(_ due: String) -> String { appFormat("chatAiDue", "Due %1$@", due) }

    static func plain(_ summary: ChatSummary) -> String {
        var out: [String] = []
        if !summary.overview.isEmpty { out.append(summary.overview) }
        func section(_ title: String, _ lines: [String]) {
            guard !lines.isEmpty else { return }
            out.append((out.isEmpty ? "" : "\n") + title + "\n" + lines.map { "- \($0)" }.joined(separator: "\n"))
        }
        section(keyPoints, summary.keyPoints)
        section(decisions, summary.decisions)
        section(actionItems, summary.actionItems.map { item in
            [item.owner.isEmpty ? nil : "\(item.owner):", item.task, item.due.isEmpty ? nil : "(\(due(item.due)))"]
                .compactMap { $0 }.joined(separator: " ")
        })
        section(openQuestions, summary.openQuestions)
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A titled block of the summary.
private struct SummarySection<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            HStack(spacing: theme.spacing.s6) {
                Image(systemName: systemImage).font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.accent)
                Text(title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
            }
            content
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A list section; nothing when the list is empty.
private struct BulletSection: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let systemImage: String
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            SummarySection(title: title, systemImage: systemImage) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s6) {
                        Text(verbatim: "•").foregroundStyle(theme.colors.tx3)
                        Text(line).foregroundStyle(theme.colors.tx)
                    }
                    .font(theme.typography.paragraph)
                }
            }
        }
    }
}

/// A task, with who is to do it and by when when the chat said.
private struct ActionItemRow: View {
    @Environment(\.appTheme) private var theme
    let item: ChatActionItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s6) {
            Image(systemName: "square").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3)
            (Text(item.owner.isEmpty ? "" : "\(item.owner)  ").fontWeight(.semibold)
                + Text(item.task)
                + Text(item.due.isEmpty ? "" : "  · \(ChatSummaryText.due(item.due))").foregroundColor(theme.colors.orange))
                .font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
        }
    }
}
