/// Ported from: test/features/chat/data/chat_video_stream_server_test.dart (range handling), chat_attachment_loader (streaming)
import CoreDomain
import Foundation
import Network
import XCTest
@testable import FeatureChat

/// A tiny HTTP/1.1 server on loopback: serves `body`, honouring `Range` with 206 or (when `honoursRange` is off) always
/// answering 200 with the whole file, like a server that ignores the header.
private final class RangeTestServer: @unchecked Sendable {
    let body: Data
    let honoursRange: Bool
    let status: Int?
    private let listener: NWListener
    private let queue = DispatchQueue(label: "range-test-server")
    private let lock = NSLock()
    private var ranges: [String?] = []
    var requestedRanges: [String?] { lock.lock(); defer { lock.unlock() }; return ranges }
    private(set) var port: UInt16 = 0

    init(body: Data, honoursRange: Bool, status: Int? = nil) throws {
        self.body = body; self.honoursRange = honoursRange; self.status = status
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws {
        listener.newConnectionHandler = { [self] c in handle(c) }
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [self] s in
                switch s {
                case .ready: port = listener.port?.rawValue ?? 0; listener.stateUpdateHandler = nil; k.resume()
                case .failed(let e): listener.stateUpdateHandler = nil; k.resume(throwing: e)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }
    var url: URL { URL(string: "http://127.0.0.1:\(port)/video.mp4")! }

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] data, _, _, _ in
            let text = String(decoding: data ?? Data(), as: UTF8.self)
            let range = text.split(separator: "\r\n").first { $0.lowercased().hasPrefix("range:") }.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            lock.lock(); ranges.append(range); lock.unlock()
            var head: String, payload = body
            if let status, status != 200 {
                head = "HTTP/1.1 \(status) X\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"; payload = Data()
            } else if honoursRange, let range, let m = range.range(of: #"bytes=(\d+)-(\d*)"#, options: .regularExpression) {
                let nums = range[m].dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
                let start = Int(nums[0]) ?? 0, end = min(Int(nums.count > 1 ? nums[1] : "") ?? body.count - 1, body.count - 1)
                payload = body.subdata(in: start..<(end + 1))
                head = "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes \(start)-\(end)/\(body.count)\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
            } else {
                head = "HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            }
            c.send(content: Data(head.utf8) + payload, completion: .contentProcessed { _ in c.cancel() })
        }
    }
}

final class VideoRangeStreamTests: XCTestCase {
    private let body = Data((0..<200).map { UInt8($0) })

    private func read(_ url: URL, from start: Int64, through end: Int64?) async -> (Data, Outcome<Void>) {
        let got = Locked(Data())
        let result = await XxdRangeStream.run(url, pinnedFingerprint: nil, start: start, end: end) { chunk in got.with { $0.append(chunk) } }
        return (got.current, result)
    }

    func testAServerThatHonoursRangeIsPassedThrough() async throws {
        let server = try RangeTestServer(body: body, honoursRange: true)
        try await server.start(); defer { server.stop() }
        let (data, result) = await read(server.url, from: 10, through: 19)
        XCTAssertNil(result.failureValue)
        XCTAssertEqual(data, body.subdata(in: 10..<20))
        XCTAssertEqual(server.requestedRanges.first ?? nil, "bytes=10-19")
    }

    func testAServerThatIgnoresRangeIsAnsweredAsIfItHonouredIt() async throws {
        let server = try RangeTestServer(body: body, honoursRange: false)
        try await server.start(); defer { server.stop() }
        let (slice, r1) = await read(server.url, from: 150, through: 159)
        XCTAssertNil(r1.failureValue)
        XCTAssertEqual(slice, body.subdata(in: 150..<160))
        let (tail, r2) = await read(server.url, from: 190, through: nil)
        XCTAssertNil(r2.failureValue)
        XCTAssertEqual(tail, body.subdata(in: 190..<200))
        let (all, r3) = await read(server.url, from: 0, through: nil)
        XCTAssertNil(r3.failureValue)
        XCTAssertEqual(all, body)
    }

    func testNotFoundAndOtherStatusesFail() async throws {
        let missing = try RangeTestServer(body: body, honoursRange: true, status: 404)
        try await missing.start(); defer { missing.stop() }
        let (_, notFound) = await read(missing.url, from: 0, through: nil)
        guard case .notFound? = notFound.failureValue else { return XCTFail("expected notFound, got \(String(describing: notFound.failureValue))") }
        let broken = try RangeTestServer(body: body, honoursRange: true, status: 500)
        try await broken.start(); defer { broken.stop() }
        let (_, failed) = await read(broken.url, from: 0, through: nil)
        XCTAssertNotNil(failed.failureValue)
    }

    func testAWholePassIsRecordedAndHandedToTheCache() async throws {
        let server = try RangeTestServer(body: body, honoursRange: true)
        try await server.start(); defer { server.stop() }
        let recorded = Locked<Data?>(nil)
        let source = UpstreamVideoSource(url: server.url, pin: nil, fileName: "clip.mp4", length: Int64(body.count), mimeType: "video/mp4") { temp in
            recorded.with { $0 = try? Data(contentsOf: temp) }; try? FileManager.default.removeItem(at: temp)
        }
        XCTAssertEqual(source.contentType, "public.mpeg-4")
        // A partial read (the index at the end) is not a recording.
        _ = await source.read(from: 100, through: nil) { _ in }
        XCTAssertNil(recorded.current)
        let got = Locked(Data())
        let result = await source.read(from: 0, through: nil) { chunk in got.with { $0.append(chunk) } }
        XCTAssertNil(result.failureValue)
        XCTAssertEqual(got.current, body)
        XCTAssertEqual(recorded.current, body)
    }

    func testContainerTypeComesFromTheMimeTypeOrTheExtension() {
        XCTAssertEqual(UpstreamVideoSource.uti(fileName: "a.mov", mimeType: nil), "com.apple.quicktime-movie")
        XCTAssertEqual(UpstreamVideoSource.uti(fileName: "a.mp4", mimeType: "video/mp4"), "public.mpeg-4")
        XCTAssertEqual(UpstreamVideoSource.uti(fileName: "noext", mimeType: "application/octet-stream"), "com.apple.quicktime-movie".isEmpty ? "" : UpstreamVideoSource.uti(fileName: "noext", mimeType: nil))
    }

    func testVideoTimeFormat() async {
        await MainActor.run {
            XCTAssertEqual(ChatVideoPlayer.format(5), "0:05")
            XCTAssertEqual(ChatVideoPlayer.format(125), "2:05")
            XCTAssertEqual(ChatVideoPlayer.format(3725), "1:02:05")
            XCTAssertEqual(ChatVideoPlayer.format(-3), "0:00")
        }
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let f) = self { f } else { nil } }
}
