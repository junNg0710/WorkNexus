import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/domain/usecases/{render_zentao_doc_html,render_zentao_doc_markdown,export_zentao_doc}.dart
/// `doc` as a standalone HTML page: its title, then the body, with plain readable styling inlined. Links and
/// images ZenTao wrote relative to its site are made absolute against `baseUrl`, so they still resolve once the
/// file is opened from disk.
public func renderZenTaoDocHtml(_ doc: ZenTaoDoc, baseUrl: String? = nil) -> String {
    let title = escapeHtml(doc.title)
    var body = doc.html.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = (baseUrl ?? "").replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    if !base.isEmpty {
        body = body.replacingOccurrences(of: #"(\s(?:src|href)=["'])(/[^/][^"']*|/)(["'])"#, with: "$1\(base)$2$3", options: .regularExpression)
    }
    return """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>\(title)</title>
    <style>
    body { max-width: 860px; margin: 40px auto; padding: 0 16px; font: 16px/1.6 -apple-system, "Segoe UI", sans-serif; color: #1f2328; }
    pre { background: #f6f8fa; padding: 12px 16px; border-radius: 6px; overflow-x: auto; }
    code { font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 0.9em; }
    table { border-collapse: collapse; }
    th, td { border: 1px solid #d0d7de; padding: 6px 12px; }
    img { max-width: 100%; }
    </style>
    </head>
    <body>
    <h1>\(title)</h1>
    \(body)
    </body>
    </html>

    """
}

private func escapeHtml(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

/// Turns a document into Markdown: its title as a heading, then the body. The Data layer supplies the real
/// HTML-to-Markdown converter (`ZenTaoDocMarkdown.render`); this is Dart's fallback when a conversion fails:
/// the body's text with its tags stripped.
public typealias ZenTaoDocMarkdownRenderer = @Sendable (ZenTaoDoc) -> String

public func zenTaoDocMarkdownFallback(_ doc: ZenTaoDoc) -> String {
    let body = doc.html.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
    let converted = body.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    return converted.isEmpty ? "# \(doc.title)" : "# \(doc.title)\n\n\(converted)"
}

/// Saves a `ZenTaoDoc` to the Downloads folder as Markdown, a standalone HTML page, or the backup of ZenTao's own
/// record - named after its title; returns the saved path.
public struct ExportZenTaoDoc: Sendable {
    private let repository: ZenTaoDocRepository
    private let markdown: ZenTaoDocMarkdownRenderer

    public init(_ repository: ZenTaoDocRepository, markdown: @escaping ZenTaoDocMarkdownRenderer = { zenTaoDocMarkdownFallback($0) }) {
        self.repository = repository
        self.markdown = markdown
    }

    public func callAsFunction(_ account: Account, _ doc: ZenTaoDoc, _ format: ZenTaoDocExportFormat) async -> Outcome<String> {
        let text: Outcome<String>
        switch format {
        case .markdown: text = .success("\(markdown(doc))\n")
        case .html: text = .success(renderZenTaoDocHtml(doc, baseUrl: account.baseUrl))
        case .backup: text = await repository.readBackup(accountId: account.id, docId: doc.id)
        }
        switch text {
        case .success(let value): return await repository.saveText(fileName: "\(doc.title).\(format.fileExtension)", text: value)
        case .failure(let f): return .failure(f)
        }
    }
}
