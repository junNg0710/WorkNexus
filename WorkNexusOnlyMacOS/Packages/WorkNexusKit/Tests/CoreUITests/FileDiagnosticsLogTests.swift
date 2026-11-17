import CoreDomain
import Foundation
import XCTest
@testable import CoreUI

final class FileDiagnosticsLogTests: XCTestCase {
    private func dir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("diag_\(UUID().uuidString)", isDirectory: true) }

    func testEntriesAreWrittenAsReadableLinesWithTheStepsUnderAnError() throws {
        let d = dir(); defer { try? FileManager.default.removeItem(at: d) }
        let log = FileDiagnosticsLog(directory: d)
        log.write(DiagnosticEntry(date: Date(timeIntervalSince1970: 0), level: .error, area: "zentao", message: "GET x → HTTP 502"),
                  trail: ["chat", "account:zt1 / zentao.bugs"])
        log.write(DiagnosticEntry(date: Date(timeIntervalSince1970: 1), level: .info, area: "app", message: "Quit"), trail: [])
        log.flush()
        let text = try String(contentsOf: log.currentFile, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasSuffix("ERROR  [zentao] GET x → HTTP 502"), lines[0])
        XCTAssertEqual(lines[1], "    after: chat › account:zt1 / zentao.bugs")
        XCTAssertTrue(lines[2].contains("INFO   [app] Quit"), lines[2])
    }

    func testAFullFileIsRotatedAndOnlySoManyAreKept() throws {
        let d = dir(); defer { try? FileManager.default.removeItem(at: d) }
        let log = FileDiagnosticsLog(directory: d, maxBytes: 300, keptFiles: 3)
        for i in 0..<40 { log.write(DiagnosticEntry(date: Date(), level: .warning, area: "t", message: "entry \(i) " + String(repeating: "x", count: 40)), trail: []) }
        log.flush()
        let names = Set(log.files().map(\.lastPathComponent))
        XCTAssertEqual(names, ["worknexus.log", "worknexus.1.log", "worknexus.2.log"])
        XCTAssertTrue(log.files().allSatisfy { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) <= 300 })
        let newest = try String(contentsOf: log.currentFile, encoding: .utf8)
        XCTAssertTrue(newest.contains("entry 39"))
        XCTAssertGreaterThan(log.totalBytes(), 0)
        log.clear()
        XCTAssertTrue(log.files().isEmpty)
    }

    func testFilesOlderThanAWeekAreRemovedAtStart() throws {
        let d = dir(); defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let old = d.appendingPathComponent("worknexus.3.log"), recent = d.appendingPathComponent("worknexus.1.log")
        try Data("old".utf8).write(to: old); try Data("new".utf8).write(to: recent)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -9 * 24 * 3600)], ofItemAtPath: old.path)
        let log = FileDiagnosticsLog(directory: d)
        log.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
    }

    func testTheExportIsAZipOfTheLogsAndADescriptionOfTheMac() throws {
        let d = dir(); defer { try? FileManager.default.removeItem(at: d) }
        let log = FileDiagnosticsLog(directory: d)
        log.write(DiagnosticEntry(date: Date(), level: .error, area: "ui", message: "boom"), trail: [])
        log.flush()
        let zip = d.appendingPathComponent("out.zip")
        try DiagnosticsArchive.export(logs: log.files(), about: DiagnosticsArchive.about(), to: zip)
        let bytes = try Data(contentsOf: zip)
        XCTAssertEqual(bytes.prefix(2), Data("PK".utf8), "a zip file")
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); listing.arguments = ["-l", zip.path]
        let pipe = Pipe(); listing.standardOutput = pipe
        try listing.run(); listing.waitUntilExit()
        let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(names.contains("worknexus.log")); XCTAssertTrue(names.contains("about.txt"))
        XCTAssertTrue(DiagnosticsArchive.about().contains("macOS"))
    }
}
