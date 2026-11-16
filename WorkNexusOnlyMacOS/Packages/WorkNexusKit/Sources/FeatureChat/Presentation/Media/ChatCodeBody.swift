/// Ported from: lib/features/chat/presentation/widgets/message_bubble_content.dart (code branch) + core/widgets/code_block.dart
import AppKit
import CoreUI
import SwiftUI

/// A code snippet: a header with its name or language and a copy button, the code in a monospaced block (long ones collapsed).
struct ChatCodeBody: View {
    @Environment(\.appTheme) private var theme
    let code: String
    let language: String?
    let name: String?
    @State private var expanded = false
    @State private var copied = false
    private static let collapsedLines = 14

    private var lines: [Substring] { code.split(separator: "\n", omittingEmptySubsequences: false) }
    private var shown: String {
        expanded || lines.count <= Self.collapsedLines ? code : lines.prefix(Self.collapsedLines).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.spacing.s8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3)
                Text(headerTitle).font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2).lineLimit(1)
                Spacer(minLength: theme.spacing.s8)
                Button(action: copy) {
                    Label(copied ? appString("codeBlockCopied", "Copied") : appString("codeBlockCopy", "Copy code"),
                          systemImage: copied ? "checkmark" : "doc.on.doc").font(theme.typography.caption)
                        .foregroundStyle(copied ? theme.colors.green : theme.colors.tx2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
            .background(theme.colors.panel2)
            ScrollView(.horizontal) {
                Text(shown).font(theme.typography.mono).foregroundStyle(theme.colors.tx).textSelection(.enabled)
                    .padding(theme.spacing.s10).fixedSize(horizontal: true, vertical: true)
            }
            if lines.count > Self.collapsedLines {
                Button { withAnimation { expanded.toggle() } } label: {
                    Text(expanded ? appString("codeBlockCollapse", "Collapse")
                                  : appString("codeBlockShowAll", "Show all {count} lines").replacingOccurrences(of: "{count}", with: "\(lines.count)"))
                        .font(theme.typography.metaStrong).foregroundStyle(theme.colors.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, theme.spacing.s6)
                }
                .buttonStyle(.plain).background(theme.colors.panel2)
            }
        }
        .frame(minWidth: 240, maxWidth: 520, alignment: .leading)
        .background(theme.colors.panel)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }

    private var headerTitle: String {
        let n = name?.trimmingCharacters(in: .whitespaces) ?? ""
        let l = language ?? SendCodeMessage.plainText
        if !n.isEmpty { return l == SendCodeMessage.plainText ? n : "\(n) · \(l)" }
        return l == SendCodeMessage.plainText ? appString("chatCode", "Code") : l
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
    }
}
