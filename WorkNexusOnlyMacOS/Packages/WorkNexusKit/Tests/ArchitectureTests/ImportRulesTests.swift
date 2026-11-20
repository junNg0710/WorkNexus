import Foundation
import XCTest

/// Swift port of test/architecture/import_rules_test.dart.
/// - Domain/ stays pure (no UI, DB or networking frameworks).
/// - Presentation/ never reaches into Data/ concerns (GRDB, CorePersistence).
/// - Hand-written line limits: Presentation ≤ 300, everything else ≤ 400.
final class ImportRulesTests: XCTestCase {
    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private func swiftFiles() -> [URL] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else { return [] }
        return (e.allObjects as! [URL]).filter { $0.pathExtension == "swift" }
    }

    private func imports(_ text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("import ") || t.hasPrefix("@testable import ") || t.hasPrefix("@preconcurrency import ") else { return nil }
            return t.split(separator: " ").last.map(String.init)
        }
    }

    private func isDomain(_ f: URL) -> Bool { f.path.contains("/Domain/") || f.path.contains("/CoreDomain/") }

    func testDomainIsPure() throws {
        let banned: Set<String> = ["SwiftUI", "AppKit", "GRDB", "CorePersistence", "CoreUI", "WebKit", "Combine", "Lottie"]
        for f in swiftFiles() where isDomain(f) {
            let bad = Set(imports(try String(contentsOf: f, encoding: .utf8))).intersection(banned)
            XCTAssertTrue(bad.isEmpty, "\(f.lastPathComponent) (domain) imports \(bad)")
        }
    }

    func testPresentationDoesNotImportData() throws {
        let banned: Set<String> = ["GRDB", "CorePersistence"]
        for f in swiftFiles() where f.path.contains("/Presentation/") {
            let bad = Set(imports(try String(contentsOf: f, encoding: .utf8))).intersection(banned)
            XCTAssertTrue(bad.isEmpty, "\(f.lastPathComponent) (presentation) imports \(bad)")
        }
    }

    func testLineLimits() throws {
        for f in swiftFiles() where !f.lastPathComponent.hasSuffix(".generated.swift") {
            let lines = try String(contentsOf: f, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            let limit = f.path.contains("/Presentation/") ? 300 : 400
            XCTAssertLessThanOrEqual(lines, limit, "\(f.path) has \(lines) lines (limit \(limit))")
        }
    }

    /// A `Text("…")` written with a string literal is a `LocalizedStringKey`: SwiftUI looks it up in the string table, and
    /// with the app's own `\.locale` in the environment that lookup re-reads the whole table (2,000+ strings) every time
    /// the text is resolved — on every card, badge and chat row that had one. UI strings go through `appString` (a
    /// `String`, shown as is); a symbol or an interpolation is written `Text(verbatim:)`.
    func testNoTextIsBuiltFromAStringLiteral() throws {
        let literal = try NSRegularExpression(pattern: #"(?<![A-Za-z_.])Text\(""#)
        let app = sourcesRoot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Sources")
        let appFiles = (FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        for f in swiftFiles() + appFiles {
            let text = try String(contentsOf: f, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let l = String(line)
                guard !l.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                XCTAssertNil(literal.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)),
                             "\(f.lastPathComponent):\(i + 1) builds a Text from a string literal; use Text(verbatim:) or appString")
            }
        }
    }
}
